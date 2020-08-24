defmodule Grav1Web.WorkerChannel do
  use Phoenix.Channel

  alias Grav1.Presence

  alias Grav1Web.WorkerAgent

  def join("worker", %{"name" => name}, socket) do
    send(self(), {:after_join, nil})
    {:ok, socket |> assign(:name, name)}
  end

  def join("worker", _, socket) do
    send(self(), {:after_join, nil})
    {:ok, socket |> assign(:name, socket.assigns.socket_id)}
  end

  def handle_info({:after_join, _}, socket) do
    presence = Presence.list(socket)

    Presence.track(socket, socket.assigns.user_id, %{name: socket.assigns.name})
    
    push(socket, "presence_state", Presence.list(socket))

    if not Map.has_key?(presence, socket.assigns.user_id) do
      #Grav1Web.RoomsLive.update()
      IO.inspect("new client!")
    end

    {:noreply, socket}
  end
  
  def terminate(_, socket) do
    Presence.untrack(socket, socket.assigns.user_id)
    presence = Presence.list(socket)
    if not Map.has_key?(presence, socket.assigns.user_id) do
      IO.inspect("client is gone :(")
    end
  end

  def handle_in("blah", %{}, socket) do
    

    {:noreply, socket}
  end
end
