defmodule Grav1.Worker do
  defstruct progress_num: 0,
            progress_den: 0,
            pass: 1,
            segment: nil,
            project: nil
end

defmodule Grav1.ClientMeta do
  defstruct socket_id: nil,
            name: "",
            user: "",
            connected: true,
            platform: nil
end

defmodule Grav1.ClientState do
  defstruct workers: [],
            max_workers: 0,
            job_queue: [],
            queue_size: 0,
            upload_queue: [],
            downloading: nil,
            uploading: []
end

defmodule Grav1.Client do
  defstruct meta: %Grav1.ClientMeta{},
            state: %Grav1.ClientState{},
            sending: %{
              downloading: nil,
              max_workers: nil
            }
end

defmodule Grav1.WorkerAgent do
  use Agent

  alias Grav1.{Client, Projects, Worker}

  defstruct clients: %{}

  def start_link(_) do
    Agent.start_link(fn -> %__MODULE__{} end, name: __MODULE__)
  end

  def connect(socket, state, meta) do
    {state, meta} = map_client(state, meta)

    Agent.update(__MODULE__, fn val ->
      new_clients =
        Map.put(val.clients, socket.assigns.socket_id, new_client(socket, state, meta))

      %{val | clients: new_clients}
    end)

    distribute_segments()
  end

  # reconnect
  def connect(socket, state, meta, socket_id) do
    {state, meta} = map_client(state, meta)

    Agent.update(__MODULE__, fn val ->
      new_clients =
        case Map.get(val.clients, socket_id) do
          nil ->
            Map.put(val.clients, socket.assigns.socket_id, new_client(socket, state, meta))

          client ->
            if client.meta.user == socket.assigns.user_id do
              new_client =
                %{
                  client
                  | meta: %{
                      client.meta
                      | socket_id: socket.assigns.socket_id,
                        connected: true
                    }
                }
                |> struct(state)

              val.clients
              |> Map.delete(socket_id)
              |> Map.put(socket.assigns.socket_id, new_client)
            else
              Map.put(val.clients, socket.assigns.socket_id, new_client(socket, state, meta))
            end
        end

      %{val | clients: new_clients}
    end)

    distribute_segments()
  end

  def disconnect(socket) do
    new_clients =
      Agent.get_and_update(__MODULE__, fn val ->
        new_clients = update_clients(val.clients, socket.assigns.socket_id, %{connected: false})

        {new_clients, %{val | clients: new_clients}}
      end)

    Grav1Web.WorkersLive.update(new_clients)
  end

  def remove(socket_id) do
    new_clients =
      Agent.get_and_update(__MODULE__, fn val ->
        new_clients = Map.delete(val.clients, socket_id)
        {new_clients, %{val | clients: new_clients}}
      end)

    Grav1Web.WorkersLive.update(new_clients)
  end

  def get_workers() do
    Agent.get(__MODULE__, fn val ->
      Enum.reduce(val.clients, [], fn {_, client}, acc ->
        acc ++ client.state.workers
      end)
    end)
  end

  defp distribute_segments(val) do
    available_clients =
      val.clients
      |> Enum.filter(fn {_, client} ->
        client.sending.downloading == nil and client.meta.connected and
          client.state.downloading == nil and client.state.max_workers > 0 and
          (length(client.state.job_queue) < client.state.queue_size or
             (length(client.state.workers) < client.state.max_workers and
                length(client.state.job_queue) == 0))
      end)

    if length(available_clients) > 0 do
      verifying_segments =
        Grav1.VerificationExecutor.get_queue()
        |> Enum.map(fn job ->
          job.segment.id
        end)

      segments =
        val.clients
        |> Projects.get_segments(verifying_segments)

      {clients_segments, _} =
        Enum.reduce(available_clients, {[], segments}, fn {key, client}, {acc, segments} ->
          client_segments =
            client.state.workers
            |> Enum.map(& &1.segment)

          filtered_segments =
            segments
            |> Enum.filter(fn segment ->
              segment.id != client.state.downloading and
                segment.id not in client.state.job_queue and
                segment.id not in client.state.upload_queue and
                segment.id not in client.state.uploading and
                segment.id not in client_segments
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
          Map.put(acc, key, %{client | sending: %{client.sending | downloading: segment.id}})
        end)

      clients_segments
      |> Enum.each(fn {{_, client}, segment} ->
        Grav1Web.WorkerChannel.push_segment(client.meta.socket_id, segment)
      end)

      {clients_segments, new_clients}
    else
      nil
    end
  end

  def distribute_segments() do
    {clients_segments, new_clients} =
      Agent.get_and_update(__MODULE__, fn val ->
        case distribute_segments(val) do
          nil ->
            {{nil, val.clients}, val}

          {clients_segments, new_clients} ->
            new_clients = Map.merge(val.clients, new_clients)
            {{clients_segments, new_clients}, %{val | clients: new_clients}}
        end
      end)

    if clients_segments != nil do
      if length(clients_segments) > 0 do
        Grav1Web.WorkersLive.update(new_clients)
      end

      new_clients
      |> Enum.group_by(fn {_, client} ->
        client.meta.user
      end)
      |> Enum.each(fn {user, clients} ->
        Grav1Web.UserLive.update(user, clients)
      end)
    end
  end

  def cancel_segments() do
    segments =
      Projects.get_segments()
      |> Map.keys()

    Agent.get(__MODULE__, fn val ->
      val.clients
    end)
    |> Enum.filter(&elem(&1, 1).meta.connected)
    |> Enum.reduce([], fn {socket_id, client}, acc ->
      workers_segments =
        client.state.workers
        |> Enum.reduce([], fn worker, acc ->
          if worker.segment not in segments do
            acc ++ [worker.segment]
          else
            acc
          end
        end)
        |> Enum.concat(
          Enum.filter(
            client.job_queue ++ [client.sending.downloading, client.state.downloading],
            fn segment ->
              segment not in segments and segment != nil
            end
          )
        )

      if length(workers_segments) > 0 do
        acc ++ [{socket_id, workers_segments}]
      else
        acc
      end
    end)
    |> Enum.each(fn {socket_id, segments} ->
      Grav1Web.WorkerChannel.cancel_segments(socket_id, segments)
    end)
  end

  def get() do
    Agent.get(__MODULE__, fn val -> val.clients end)
  end

  defp update_clients(clients, id, opts, sending \\ %{}) do
    case Map.get(clients, id) do
      nil ->
        clients

      client ->
        client = %{
          client
          | state: struct(client.state, opts),
            sending: Map.merge(client.sending, sending)
        }

        new_sending =
          client.sending
          |> Enum.map(fn pair ->
            case pair do
              {_, nil} ->
                pair

              {:downloading, segment} ->
                if segment == client.state.downloading or
                     segment in client.state.job_queue or
                     segment in client.state.upload_queue or
                     segment in client.state.uploading do
                  {:downloading, nil}
                else
                  case Projects.get_segment(segment) do
                    nil ->
                      {:downloading, nil}

                    segment ->
                      Grav1Web.WorkerChannel.push_segment(id, segment)
                      pair
                  end
                end

              _ ->
                pair
            end
          end)
          |> Map.new()

        Map.put(clients, id, %{client | sending: new_sending})
    end
  end

  def update_workers(socket_id, workers) do
    id = to_string(socket_id)

    Agent.get_and_update(__MODULE__, fn val ->
      case Map.get(val.clients, id) do
        nil ->
          {val.clients, val}

        client ->
          {val.clients,
           %{
             val
             | clients:
                 Map.put(val.clients, id, %{client | state: %{client.state | workers: workers}})
           }}
      end
    end)
  end

  def update_client(socket_id, opts, sending \\ %{}) do
    Agent.get_and_update(__MODULE__, fn val ->
      new_clients = update_clients(val.clients, to_string(socket_id), opts, sending)

      {new_clients, %{val | clients: new_clients}}
    end)
    |> Grav1Web.WorkersLive.update()
  end

  defp new_client(socket, state, meta) do
    state = struct(%Grav1.ClientState{}, state)

    meta =
      %Grav1.ClientMeta{}
      |> struct(meta)
      |> Map.put(:user, socket.assigns.user_id)
      |> Map.put(:socket_id, socket.assigns.socket_id)

    %Client{state: state, meta: meta}
  end

  defp map_client(state, meta) do
    new_state = for {k, v} <- state, into: %{}, do: {String.to_atom(k), v}
    new_meta = for {k, v} <- meta, into: %{}, do: {String.to_atom(k), v}

    new_workers =
      new_state.workers
      |> Enum.reduce([], fn worker, acc ->
        worker =
          worker
          |> Enum.map(fn {a, b} ->
            {String.to_atom(a), b}
          end)
          |> Map.new()

        acc ++ [struct(%Worker{}, worker)]
      end)

    {%{new_state | workers: new_workers}, new_meta}
  end
end
