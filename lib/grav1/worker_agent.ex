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

    Grav1Web.WorkersLive.update()
  end

  # reconnect
  def connect(socket, state, socket_id) do
    state = map_client(state)

    Agent.update(__MODULE__, fn val ->
      new_clients = case Map.get(val.clients, socket_id) do
        nil ->
          Map.put(val.clients, socket.assigns.socket_id, new_client(socket, state))

        client ->
          if client.user == socket.assigns.user_id do
            new_client =
              %{client | socket_id: socket.assigns.socket_id, connected: true}
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

    Grav1Web.WorkersLive.update()
  end

  def disconnect(socket) do
    Agent.update(__MODULE__, fn val ->
      new_clients = case Map.get(val.clients, socket.assigns.socket_id) do
        nil ->
          val.clients

        client ->
          Map.put(val.clients, socket.assigns.socket_id, %{client | connected: false})
      end
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

  defp new_client(socket, state) do
    %Client{
      user: socket.assigns.user_id,
      socket_id: socket.assigns.socket_id,
      name: socket.assigns.name
    }
    |> Map.merge(state)
  end

  def get_workers() do
    Agent.get(__MODULE__, fn val ->
      Enum.reduce(val.clients, [], fn {_, client}, acc ->
        acc ++ client.workers
      end)
    end)
  end

  def get() do
    Agent.get(__MODULE__, fn val -> val end)
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
