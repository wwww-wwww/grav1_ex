defmodule Grav1Web.WorkerChannel do
  use Phoenix.Channel

  alias Phoenix.Socket.Broadcast
  alias Grav1Web.Endpoint
  alias Grav1.WorkerAgent

  def join("worker", %{"name" => name, "state" => state, "id" => id}, socket) do
    send(self(), {:reconnect, id, state})
    :ok = Endpoint.subscribe("worker:" <> socket.assigns.socket_id)
    {:ok, socket.assigns.socket_id, socket |> assign(:name, name)}
  end

  def join("worker", %{"name" => name, "state" => state}, socket) do
    send(self(), {:after_join, state})
    :ok = Endpoint.subscribe("worker:" <> socket.assigns.socket_id)
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

  def handle_info(%Broadcast{topic: _, event: "push_job", payload: payload}, socket) do
    push(socket, "push_job", payload)
    {:noreply, socket}
  end

  def handle_info(%Broadcast{topic: _, event: ev, payload: payload}, socket) do
    push(socket, ev, payload)
    {:noreply, socket}
  end

  def handle_in("blah", %{}, socket) do
    {:noreply, socket}
  end

  def push_job(socketid, job) do
    params = %{
      segment_id: job.id,
      url: "some url",
      frames: job.frames
    }

    Endpoint.broadcast("worker:#{socketid}", "push_job", params)
  end
end
