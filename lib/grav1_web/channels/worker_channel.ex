defmodule Grav1Web.WorkerChannel do
  use Phoenix.Channel

  alias Grav1.WorkerAgent

  def join("worker", %{"name" => name}, socket) do
    send(self(), {:after_join, nil})
    :ok = Grav1Web.Endpoint.subscribe("worker:" <> socket.assigns.socket_id)
    {:ok, socket |> assign(:name, name)}
  end

  def join("worker", _, socket) do
    send(self(), {:after_join, nil})
    :ok = Grav1Web.Endpoint.subscribe("worker:" <> socket.assigns.socket_id)
    {:ok, socket |> assign(:name, socket.assigns.socket_id)}
  end

  def handle_info({:after_join, _}, socket) do
    WorkerAgent.connect(socket)

    {:noreply, socket}
  end
  
  def terminate(_, socket) do
    WorkerAgent.disconnect(socket)
    IO.inspect("client is gone :(")
  end

  def handle_info(%Phoenix.Socket.Broadcast{topic: _, event: ev, payload: payload}, socket) do
    push(socket, ev, payload)
    {:noreply, socket}
  end

  def handle_in("blah", %{}, socket) do
    {:noreply, socket}
  end
end
