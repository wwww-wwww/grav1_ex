defmodule Grav1.Client do
  defstruct socket_id: nil,
            name: "",
            user: "",
            connected: true,
            workers: [],
            download_queue: [],
            upload_queue: [],
            dowloading: nil,
            uploading: nil
end

defmodule Grav1.WorkerAgent do
  use Agent

  alias Grav1Web.Endpoint

  alias Grav1.{Repo, User, Client, Projects}

  defstruct clients: %{}

  def start_link(_) do
    Agent.start_link(fn -> %__MODULE__{} end, name: __MODULE__)
  end

  def connect(socket, state) do
    Agent.update(__MODULE__, fn val ->
      new_clients = Map.put(val.clients, socket.assigns.socket_id, new_client(socket, state))
      %{val | clients: new_clients}
    end)

    Grav1Web.WorkersLive.update()
  end

  # reconnect
  def connect(socket, state, socket_id) do
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

  def get() do
    Agent.get(__MODULE__, fn val -> val end)
  end

  def chat(channel, socket, msg) do
    {:noreply}
  end
end
