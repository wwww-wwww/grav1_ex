defmodule Grav1.Worker do
  defstruct progress_num: 0,
            progress_den: 0,
            pass: 1,
            segment: nil
end

defmodule Grav1.Client do
  defstruct socket_id: nil,
            name: "",
            user: "",
            connected: true,
            sending_job: nil,
            workers: [],
            max_workers: 0,
            job_queue: [],
            queue_size: 0,
            upload_queue: [],
            downloading: nil,
            uploading: nil,
            platform: nil
end

defmodule Grav1.WorkerAgent do
  use Agent

  alias Grav1.{Client, Projects, Worker}

  defstruct clients: %{}

  def start_link(_) do
    Agent.start_link(fn -> %__MODULE__{} end, name: __MODULE__)
  end

  def connect(socket, state) do
    state = map_client(state)

    Agent.update(__MODULE__, fn val ->
      new_clients = Map.put(val.clients, socket.assigns.socket_id, new_client(socket, state))
      %{val | clients: new_clients}
    end)

    if not distribute_segments() do
      Grav1Web.WorkersLive.update()
    end
  end

  # reconnect
  def connect(socket, state, socket_id) do
    state = map_client(state)

    Agent.update(__MODULE__, fn val ->
      new_clients =
        case Map.get(val.clients, socket_id) do
          nil ->
            Map.put(val.clients, socket.assigns.socket_id, new_client(socket, state))

          client ->
            if client.user == socket.assigns.user_id do
              new_client =
                %{
                  client
                  | socket_id: socket.assigns.socket_id,
                    connected: true
                }
                |> struct(state)

              val.clients
              |> Map.delete(socket_id)
              |> Map.put(socket.assigns.socket_id, new_client)
            else
              Map.put(val.clients, socket.assigns.socket_id, new_client(socket, state))
            end
        end

      %{val | clients: new_clients}
    end)

    if not distribute_segments() do
      Grav1Web.WorkersLive.update()
    end
  end

  def disconnect(socket) do
    Agent.update(__MODULE__, fn val ->
      new_clients = update_clients(val.clients, socket.assigns.socket_id, %{connected: false})

      %{val | clients: new_clients}
    end)

    Grav1Web.WorkersLive.update()
  end

  def remove(socket_id) do
    Agent.update(__MODULE__, fn val ->
      new_clients = Map.delete(val.clients, socket_id)
      %{val | clients: new_clients}
    end)

    Grav1Web.WorkersLive.update()
  end

  def get_workers() do
    Agent.get(__MODULE__, fn val ->
      Enum.reduce(val.clients, [], fn {_, client}, acc ->
        acc ++ client.workers
      end)
    end)
  end

  def distribute_segments(val) do
    available_clients =
      val.clients
      |> Enum.filter(fn {_, client} ->
        client.sending_job == nil and
          client.connected and
          client.downloading == nil and
          (length(client.job_queue) < client.queue_size or
             (length(Enum.filter(client.workers, &(&1.segment == nil))) > 0 and
                length(client.job_queue) == 0))
      end)

    verifying_segments =
      Grav1.VerificationExecutor.get_queue()
      |> Enum.map(fn job ->
        job.segment.id
      end)

    segments =
      val.clients
      |> Projects.get_segments(length(available_clients), verifying_segments)

    {clients_segments, _} =
      Enum.reduce(available_clients, {[], segments}, fn {key, client}, {acc, segments} ->
        filtered_segments =
          segments
          |> Enum.filter(fn segment ->
            segment.id != client.downloading and
              segment.id != client.uploading and
              segment.id not in client.job_queue and
              segment.id not in client.upload_queue
          end)

        case List.first(filtered_segments) do
          nil ->
            {acc, segments}

          new_segment ->
            new_segments =
              segments
              |> Enum.filter(fn segment -> segment.id != new_segment.id end)

            {acc ++ [{{key, client}, new_segment}], new_segments}
        end
      end)

    new_clients =
      clients_segments
      |> Enum.reduce(%{}, fn {{key, client}, segment}, acc ->
        Map.put(acc, key, %{client | sending_job: segment.id})
      end)

    clients_segments
    |> Enum.each(fn {{_, client}, segment} ->
      Grav1Web.WorkerChannel.push_segment(client.socket_id, segment)
    end)

    {clients_segments, new_clients}
  end

  def distribute_segments() do
    clients =
      Agent.get_and_update(__MODULE__, fn val ->
        {clients_segments, new_clients} = distribute_segments(val)

        {clients_segments, %{val | clients: Map.merge(val.clients, new_clients)}}
      end)

    if length(clients) > 0 do
      Grav1Web.WorkersLive.update()
      true
    else
      false
    end
  end

  def distribute_segments_cast() do
    Agent.cast(__MODULE__, fn val ->
      {_clients, new_clients} = distribute_segments(val)

      %{val | clients: Map.merge(val.clients, new_clients)}
    end)
  end

  def cancel_segments() do
    segments =
      Projects.get_segments()
      |> Map.keys()

    Agent.get(__MODULE__, fn val ->
      val.clients
    end)
    |> Enum.reduce([], fn {socket_id, client}, acc ->
      workers_segments =
        client.workers
        |> Enum.reduce([], fn worker, acc ->
          if worker.segment != nil and worker.segment not in segments do
            acc ++ [worker.segment]
          else
            acc
          end
        end)
        |> Enum.concat(
          Enum.filter(client.job_queue, fn segment ->
            segment not in segments
          end)
        )

      client_segments =
        if client.sending_job not in segments do
          workers_segments ++ [client.sending_job]
        else
          workers_segments
        end

      if length(client_segments) > 0 do
        acc ++ [{socket_id, client_segments}]
      else
        acc
      end
    end)
    |> Enum.each(fn {socket_id, segments} ->
      Grav1Web.WorkerChannel.cancel_segments(socket_id, segments)
    end)
  end

  def get() do
    Agent.get(__MODULE__, fn val -> val end)
  end

  defp update_clients(clients, id, opts) do
    case Map.get(clients, id) do
      nil ->
        clients

      client ->
        new_client = struct(client, opts)

        if client.sending_job != nil and new_client.sending_job != nil do
          case Projects.get_segment(new_client.sending_job) do
            nil ->
              Map.put(clients, id, %{new_client | sending_job: nil})

            segment ->
              Grav1Web.WorkerChannel.push_segment(id, segment)
              clients
          end
        else
          Map.put(clients, id, new_client)
        end
    end
  end

  def update_workers(socket_id, workers) do
    id = to_string(socket_id)

    Agent.update(__MODULE__, fn val ->
      case Map.get(val.clients, id) do
        nil ->
          val

        client ->
          if client.workers
             |> Enum.zip(workers)
             |> Enum.all?(fn x ->
               {old_worker, new_worker} = x

               new_worker.segment == old_worker.segment and
                 (new_worker.pass >= old_worker.pass or
                    new_worker.progress_num >= old_worker.progress_num)
             end) do
            %{val | clients: Map.put(val.clients, id, %{client | workers: workers})}
          else
            val
          end
      end
    end)
  end

  def update_client(socket_id, opts) do
    Agent.update(__MODULE__, fn val ->
      new_clients = update_clients(val.clients, to_string(socket_id), opts)

      %{val | clients: new_clients}
    end)
  end

  defp new_client(socket, state) do
    %Client{
      user: socket.assigns.user_id,
      socket_id: socket.assigns.socket_id
    }
    |> struct(state)
  end

  defp map_client(state) do
    new_state = for {k, v} <- state, into: %{}, do: {String.to_atom(k), v}

    new_workers =
      new_state.workers
      |> Enum.reduce([], fn worker, acc ->
        acc ++ [struct(Worker, worker)]
      end)

    %{new_state | workers: new_workers}
  end
end
