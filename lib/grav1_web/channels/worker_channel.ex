defmodule Grav1Web.WorkerChannel do
  use Phoenix.Channel

  alias Phoenix.Socket.Broadcast
  alias Grav1Web.Endpoint
  alias Grav1.WorkerAgent

  def join(
        "worker",
        %{"versions" => versions, "state" => state, "meta" => meta, "id" => id, "uuid" => uuid},
        socket
      ) do
    bad_versions =
      versions
      |> Enum.filter(&check_version(&1))
      |> Enum.map(&elem(&1, 0))

    encoders = Map.keys(versions)

    missing_encoders =
      Application.fetch_env!(:grav1, :encoders)
      |> Enum.filter(&(to_string(&1) not in encoders))

    cond do
      length(missing_encoders) > 0 ->
        {:error, %{reason: "missing encoders", data: missing_encoders}}

      length(bad_versions) > 0 ->
        {:error, %{reason: "bad versions", data: bad_versions}}

      true ->
        {:ok, client} =
          if String.length(id) > 0 do
            WorkerAgent.connect(socket, state, meta, id, uuid)
          else
            WorkerAgent.connect(socket, state, meta)
          end

        :ok = Endpoint.subscribe("worker:" <> socket.assigns.socket_id)

        WorkerAgent.cancel_segments(Grav1.Projects.get_segments_keys())
        WorkerAgent.distribute_segments()

        {:ok, %{sock_id: socket.assigns.socket_id, uuid: client.meta.uuid}, socket}
    end
  end

  def join("worker", %{"versions" => versions, "state" => state, "meta" => meta}, socket) do
    join(
      "worker",
      %{"versions" => versions, "state" => state, "meta" => meta, "id" => "", "uuid" => ""},
      socket
    )
  end

  defp check_version({encoder, version}) do
    case Application.fetch_env(:versions, String.to_atom(encoder)) do
      :error ->
        false

      {:ok, ^version} ->
        false

      _ ->
        true
    end
  end

  def terminate(_, socket) do
    WorkerAgent.disconnect(socket)
    IO.inspect("client is gone :(")
  end

  def handle_info(%Broadcast{topic: _, event: "push_segment", payload: payload}, socket) do
    push(socket, "push_segment", payload)
    {:noreply, socket}
  end

  def handle_info(%Broadcast{topic: _, event: "cancel_segments", payload: payload}, socket) do
    push(socket, "cancel", payload)
    {:noreply, socket}
  end

  def handle_info(%Broadcast{topic: _, event: "set_workers", payload: payload}, socket) do
    push(socket, "set_workers", payload)
    {:noreply, socket}
  end

  def handle_info(%Broadcast{topic: _, event: ev, payload: payload}, socket) do
    IO.inspect(ev)
    push(socket, ev, payload)
    {:noreply, socket}
  end

  def handle_in("recv_segment", %{"downloading" => downloading}, socket) do
    WorkerAgent.update_client(
      socket.assigns.socket_id,
      state: %{downloading: downloading},
      sending: %{downloading: nil}
    )

    WorkerAgent.distribute_segments()

    {:noreply, socket}
  end

  def handle_in(
        "update",
        %{
          "workers" => workers,
          "max_workers" => max_workers,
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
      state: %{
        job_queue: job_queue,
        upload_queue: upload_queue,
        downloading: downloading,
        uploading: uploading,
        workers: new_workers,
        max_workers: max_workers
      }
    )

    WorkerAgent.distribute_segments()

    {:noreply, socket}
  end

  def push_segment(socketid, segment) do
    params = %{
      segment_id: segment.id,
      project_id: segment.project_id,
      file: segment.file,
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

  def push_max_workers(socketid, n) do
    Endpoint.broadcast("worker:#{socketid}", "set_workers", %{n: n})
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

    new_clients = Grav1.WorkerAgent.update_workers(socket.assigns.socket_id, new_workers)

    if Grav1.RateLimit.can_execute?("worker_update", 1 / 10) do
      Grav1Web.WorkersLive.update(new_clients)
    end

    try do
      Grav1.Projects.get_projects()
      |> Enum.reduce([], fn {_, project}, acc ->
        changed_segments =
          project.segments
          |> Enum.reduce([], fn {_, segment}, acc ->
            working =
              new_workers
              |> Enum.filter(&(segment.id == &1.segment))

            if length(working) > 0 do
              acc ++ [{segment, working}]
            else
              acc
            end
          end)

        if length(changed_segments) > 0 do
          acc ++ [{project, changed_segments}]
        else
          acc
        end
      end)
      |> Enum.each(fn {project, changed_segments} ->
        Grav1Web.ProjectsLive.update_segments(project, changed_segments)
      end)
    catch
      e ->
        IO.inspect(e)
    end

    {:noreply, socket}
  end
end
