defmodule Grav1.Worker do
  defstruct client: nil,
            progress_num: 0,
            progress_den: 0,
            pass: 1,
            segment: nil
end

defmodule Grav1.Client do
  defstruct socket_id: nil,
            name: "",
            user: "",
            connected: true,
            sending_job: false,
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

  alias Grav1Web.Endpoint

  alias Grav1.{Repo, User, Client, Projects, Worker}

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
                    connected: true,
                    sending_job: false
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
      new_clients = update_client(val.clients, socket.assigns.socket_id, %{connected: false})

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

  def update_client(socket_id, opts) do
    Agent.update(__MODULE__, fn val ->
      new_clients = update_client(val.clients, to_string(socket_id), opts)

      %{val | clients: new_clients}
    end)
  end

  def distribute_segments() do
    clients =
      Agent.get_and_update(__MODULE__, fn val ->
        available_clients =
          val.clients
          |> Enum.filter(fn {_, client} ->
            not client.sending_job and
              client.downloading == nil and
              (length(client.job_queue) < client.queue_size or
                 (length(Enum.filter(client.workers, &(&1.segment == nil))) > 0 and
                    length(client.job_queue) == 0))
          end)

        segments =
          val.clients
          |> Projects.get_segments(length(available_clients))

        {client_segment, _} =
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
          client_segment
          |> Enum.reduce(%{}, fn {{key, client}, _}, acc ->
            Map.put(acc, key, %{client | sending_job: true})
          end)

        {client_segment, %{val | clients: Map.merge(val.clients, new_clients)}}
      end)

    clients
    |> Enum.each(fn {{_, client}, job} ->
      Grav1Web.WorkerChannel.push_segment(client.socket_id, job)
    end)

    if length(clients) > 0 do
      Grav1Web.WorkersLive.update()
      true
    else
      false
    end
  end

  def get() do
    Agent.get(__MODULE__, fn val -> val end)
  end

  defp update_client(clients, id, opts) do
    case Map.get(clients, id) do
      nil ->
        clients

      client ->
        Map.put(clients, id, struct(client, opts))
    end
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
