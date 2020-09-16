defmodule Grav1Web.WorkerChannel do
  use Phoenix.Channel

  alias Phoenix.Socket.Broadcast
  alias Grav1Web.Endpoint
  alias Grav1.{WorkerAgent, Worker}

  def join("worker", %{"state" => state, "id" => id}, socket) do
    send(self(), {:reconnect, id, state})
    :ok = Endpoint.subscribe("worker:" <> socket.assigns.socket_id)
    {:ok, socket.assigns.socket_id, socket}
  end

  def join("worker", %{"state" => state}, socket) do
    send(self(), {:after_join, state})
    :ok = Endpoint.subscribe("worker:" <> socket.assigns.socket_id)
    {:ok, socket.assigns.socket_id, socket}
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

  def handle_info(%Broadcast{topic: _, event: "cancel_segments", payload: payload}, socket) do
    push(socket, "cancel", payload)
    {:noreply, socket}
  end

  def handle_info(%Broadcast{topic: _, event: ev, payload: payload}, socket) do
    IO.inspect(ev)
    push(socket, ev, payload)
    {:noreply, socket}
  end

  def handle_in("recv_segment", %{"downloading" => downloading}, socket) do
    WorkerAgent.update_client(socket.assigns.socket_id, %{
      downloading: downloading,
      sending_job: nil
    })

    if not WorkerAgent.distribute_segments() do
      Grav1Web.WorkersLive.update()
    end

    {:noreply, socket}
  end

  def handle_in(
        "update",
        %{
          "workers" => workers,
          "job_queue" => job_queue,
          "upload_queue" => upload_queue,
          "downloading" => downloading,
          "uploading" => uploading
        },
        socket
      ) do
    new_workers =
      workers
      |> Enum.map(fn worker ->
        worker = for {k, v} <- worker, into: %{}, do: {String.to_atom(k), v}
        struct(Grav1.Worker, worker)
      end)

    WorkerAgent.update_client(
      socket.assigns.socket_id,
      %{
        job_queue: job_queue,
        upload_queue: upload_queue,
        downloading: downloading,
        uploading: uploading,
        workers: new_workers
      }
    )

    if not WorkerAgent.distribute_segments() do
      Grav1Web.WorkersLive.update()
    end

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

  def cancel_segments(socketid, segments) do
    Endpoint.broadcast("worker:#{socketid}", "cancel_segments", %{segments: segments})
  end

  def push_test(socketid, params) do
    Endpoint.broadcast("worker:#{socketid}", "test", params)
  end
end

defmodule Grav1Web.WorkerProgressChannel do
  use Phoenix.Channel

  def join("worker_progress", _, socket) do
    {:ok, socket}
  end

  def handle_in("update_workers", %{"workers" => workers}, socket) do
    new_workers =
      workers
      |> Enum.map(fn worker ->
        worker = for {k, v} <- worker, into: %{}, do: {String.to_atom(k), v}
        struct(Grav1.Worker, worker)
      end)

    Grav1.WorkerAgent.update_workers(socket.assigns.socket_id, new_workers)

    if Grav1.RateLimit.can_execute?("worker_update", 1 / 10) do
      Grav1Web.WorkersLive.update()
    end

    segments =
      new_workers
      |> Enum.map(fn worker -> worker.segment end)

    Grav1.Projects.get_projects()
    |> Enum.filter(fn {_, project} ->
      project.state == :ready and
        Enum.any?(Map.keys(project.segments), fn x -> x in segments end)
    end)
    |> Enum.each(fn {_, project} ->
      Grav1Web.ProjectsLive.update_segments(project, true)
    end)

    {:noreply, socket}
  end
end
