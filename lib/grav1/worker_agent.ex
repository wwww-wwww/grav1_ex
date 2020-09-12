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
            uploading: nil
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

    distribute_segments()

    Grav1Web.WorkersLive.update()
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
                |> Map.merge(state)

              val.clients
              |> Map.delete(socket_id)
              |> Map.put(socket.assigns.socket_id, new_client)
            else
              Map.put(val.clients, socket.assigns.socket_id, new_client(socket, state))
            end
        end

      %{val | clients: new_clients}
    end)

    distribute_segments()

    Grav1Web.WorkersLive.update()
  end

  def disconnect(socket) do
    Agent.update(__MODULE__, fn val ->
      new_clients = update_client(val.clients, socket.assigns.socket_id, %{connected: false})

      %{val | clients: new_clients}
    end)

    Grav1Web.WorkersLive.update()
  end

  def remove(socket) do
    Agent.update(__MODULE__, fn val ->
      new_clients = Map.delete(val.clients, socket.assigns.socket_id)
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
          |> Enum.filter(fn {key, client} ->
            client.downloading == nil and not client.sending_job
          end)

        segments =
          val.clients
          |> Enum.reduce([], fn {_, client}, acc ->
            acc ++ client.workers
          end)
          |> Projects.get_segments(length(available_clients))

        client_segment = Enum.zip(available_clients, segments)

        new_clients =
          client_segment
          |> Enum.reduce(%{}, fn {{key, client}, segment}, acc ->
            Map.put(acc, key, %{client | sending_job: true})
          end)

        {client_segment, %{val | clients: Map.merge(val.clients, new_clients)}}
      end)

    clients
    |> Enum.each(fn {{_, client}, job} ->
      Grav1Web.WorkerChannel.push_segment(client.socket_id, job)
    end)
  end

  def get() do
    Agent.get(__MODULE__, fn val -> val end)
  end

  defp update_client(clients, id, opts) do
    case Map.get(clients, id) do
      nil ->
        clients

      client ->
        Map.put(clients, id, Map.merge(client, opts))
    end
  end

  defp new_client(socket, state) do
    %Client{
      user: socket.assigns.user_id,
      socket_id: socket.assigns.socket_id,
      name: socket.assigns.name
    }
    |> Map.merge(state)
  end

  defp map_client(state) do
    %{
      "workers" => workers,
      "max_workers" => max_workers,
      "job_queue" => job_queue,
      "upload_queue" => upload_queue,
      "downloading" => downloading,
      "uploading" => uploading,
      "queue_size" => queue_size
    } = state

    new_workers =
      workers
      |> Enum.reduce([], fn worker, acc ->
        acc ++ [struct(Worker, worker)]
      end)

    %{
      workers: new_workers,
      max_workers: max_workers,
      job_queue: job_queue,
      upload_queue: upload_queue,
      queue_size: queue_size,
      downloading: downloading,
      uploading: uploading
    }
  end
end
