defmodule Grav1.Client do
  defstruct socket_id: nil,
    workers: [],
    name: "",
    user: ""
end

defmodule Grav1.WorkerAgent do
  use Agent

  alias Grav1Web.Endpoint
  
  alias Grav1.{Repo, User, Client}

  alias Phoenix.HTML

  defstruct clients: %{}

  def start_link(_) do
    Agent.start_link(fn -> %__MODULE__{} end, name: __MODULE__)
  end

  def connect(socket) do
    Agent.update(__MODULE__, fn val ->
      client = %Client{user: socket.assigns.user_id, socket_id: socket.assigns.socket_id, name: socket.assigns.name}
      new_clients = Map.put(val.clients, socket.assigns.socket_id, client)
      %{val | clients: new_clients}
    end)
    Grav1Web.WorkersLive.update()
  end

  def disconnect(socket) do
    Agent.update(__MODULE__, fn val ->
      new_clients = Map.delete(val.clients, socket.assigns.socket_id)
      %{val | clients: new_clients}
    end)
    Grav1Web.WorkersLive.update()
  end

  def get() do
    Agent.get(__MODULE__, fn val -> val end)
  end

  def chat(channel, socket, msg) do
    {:noreply}
  end
end
