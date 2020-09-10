defmodule Grav1Web.WorkerChannel do
  use Phoenix.Channel

  alias Grav1.WorkerAgent

  def join("worker", %{"name" => name, "state" => state, "id" => id}, socket) do
    send(self(), {:reconnect, id, state})
    :ok = Grav1Web.Endpoint.subscribe("worker:" <> socket.assigns.socket_id)
    {:ok, socket.assigns.socket_id, socket |> assign(:name, name)}
  end

  def join("worker", %{"name" => name, "state" => state}, socket) do
    send(self(), {:after_join, state})
    :ok = Grav1Web.Endpoint.subscribe("worker:" <> socket.assigns.socket_id)
    {:ok, socket.assigns.socket_id, socket |> assign(:name, name)}
  end

  def join("worker", %{"state" => state, "id" => id}, socket) do
    join("worker", %{"name" => "", "state" => state, "id" => id}, socket)
  end

  def join("worker", %{"state" => state}, socket) do
    join("worker", %{"name" => "", "state" => state}, socket)
  end

  def terminate(_, socket) do
    WorkerAgent.disconnect(socket)
    IO.inspect("client is gone :(")
  end

  def handle_info({:reconnect, id, state}, socket) do
    WorkerAgent.connect(socket, state, id)

    {:noreply, socket}
  end

  def handle_info({:after_join, state}, socket) do
    WorkerAgent.connect(socket, state)

    {:noreply, socket}
  end

  def handle_info(%Phoenix.Socket.Broadcast{topic: _, event: ev, payload: payload}, socket) do
    push(socket, ev, payload)
    {:noreply, socket}
  end

  def handle_in("blah", %{}, socket) do
    {:noreply, socket}
  end
end
