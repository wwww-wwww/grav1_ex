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

  def handle_info(%Broadcast{topic: _, event: "push_segment", payload: payload}, socket) do
    push(socket, "push_segment", payload)
    {:noreply, socket}
  end

  def handle_info(%Broadcast{topic: _, event: ev, payload: payload}, socket) do
    push(socket, ev, payload)
    {:noreply, socket}
  end

  def handle_in("recv_segment", %{"downloading" => downloading}, socket) do
    WorkerAgent.update_client(socket.assigns.socket_id, %{
      downloading: downloading,
      sending_segment: false
    })

    WorkerAgent.distribute_segments()

    Grav1Web.WorkersLive.update()

    {:noreply, socket}
  end

  def push_segment(socketid, segment) do
    params = %{
      segment_id: segment.id,
      start: segment.start,
      frames: segment.frames,
      encoder: segment.project.encoder,
      passes: 2,
      encoder_params: segment.project.encoder_params,
      ffmpeg_params: segment.project.ffmpeg_params,
      grain_table: "",
      split_name: "p#{segment.project.id}s#{segment.file}",
      url: Grav1Web.Router.Helpers.api_url(%URI{}, :get_segment, segment.id)
    }

    Endpoint.broadcast("worker:#{socketid}", "push_segment", params)
  end
end
