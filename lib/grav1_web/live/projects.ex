defmodule Grav1Web.ProjectsLive do
  use Phoenix.LiveView

  @topic "projects_live"

  alias Grav1.{Projects, Project, RateLimit}
  alias Grav1Web.Endpoint

  def render(assigns) do
    Grav1Web.PageView.render("projects.html", assigns)
  end

  def mount(socket, page \\ nil) do
    if connected?(socket), do: Grav1Web.Endpoint.subscribe(@topic)

    new_socket =
      socket
      |> assign(projects: Projects.get_projects())
      |> assign(project_changeset: Project.changeset(%Project{}))
      |> assign(page: page)

    {:ok, new_socket}
  end

  def mount(%{"id" => id}, _, socket) do
    case Projects.get_project(id) do
      nil ->
        mount(socket)

      project ->
        page =
          live_component(socket, Grav1Web.ProjectComponent,
            id: "project:#{project.id}",
            project: project,
            page:
              live_component(socket, Grav1Web.ProjectSegmentsComponent,
                id: "#{Grav1Web.ProjectSegmentsComponent}:#{project.id}",
                segments: get_segments(project)
              )
          )

        mount(socket, page)
    end
  end

  def mount(_, _, socket) do
    mount(socket)
  end

  def handle_params(_, _, socket) do
    {:noreply, socket}
  end

  def handle_event(
        "add_project",
        %{
          "files" => files,
          "encoder" => encoder,
          "encoder_params" => encoder_params,
          "extra_params" => %{
            "split" => %{"min_frames" => min_frames, "max_frames" => max_frames},
            "name" => name,
            "priority" => priority,
            "on_complete" => on_complete,
            "on_complete_params" => on_complete_params,
            "ffmpeg_params" => ffmpeg_params
          }
        },
        socket
      ) do
    case Projects.add_project(files, %{
           encoder: encoder,
           encoder_params: encoder_params,
           ffmpeg_params: ffmpeg_params,
           split_min_frames: min_frames,
           split_max_frames: max_frames,
           name: name,
           priority: priority,
           on_complete: on_complete,
           on_complete_params: on_complete_params
         }) do
      {:error, reason} ->
        {:reply, %{success: false, reason: reason}, socket}

      _ ->
        {:reply, %{success: true}, socket}
    end
  end

  def view_project_page(socket, page, id, assign) do
    case Projects.get_project(id) do
      nil ->
        {:noreply, socket |> assign(page: nil)}

      project ->
        {:noreply,
         socket
         |> assign(
           page:
             live_component(socket, Grav1Web.ProjectComponent,
               id: "project:#{project.id}",
               project: project,
               page:
                 live_component(socket, page, [id: "#{page}:#{project.id}"] ++ assign.(project))
             )
         )}
    end
  end

  def handle_event("view_project", %{"id" => id}, socket) do
    view_project_page(socket, Grav1Web.ProjectSegmentsComponent, id, fn project ->
      [segments: get_segments(project)]
    end)
  end

  def handle_event("view_project_log", %{"id" => id}, socket) do
    view_project_page(socket, Grav1Web.ProjectLogComponent, id, fn project ->
      [log: project.log]
    end)
  end

  def handle_event("view_project_settings", %{"id" => id}, socket) do
    view_project_page(socket, Grav1Web.ProjectSettingsComponent, id, fn project ->
      [project: project]
    end)
  end

  # update project list and project
  def handle_info(
        %{topic: @topic, event: "update", payload: %{project: project, projects: true}},
        socket
      ) do
    send_update(Grav1Web.ProjectComponent, id: "project:#{project.id}", project: project)
    {:noreply, socket |> assign(projects: Projects.get_projects())}
  end

  # update only project list
  def handle_info(
        %{topic: @topic, event: "update_projects", payload: %{projects: projects}},
        socket
      ) do
    {:noreply, socket |> assign(projects: projects)}
  end

  # update only project
  def handle_info(%{topic: @topic, event: "update_project", payload: %{project: project}}, socket) do
    send_update(Grav1Web.ProjectComponent, id: "project:#{project.id}", project: project)
    {:noreply, socket}
  end

  # update only project logs
  def handle_info(%{topic: @topic, event: "log", payload: %{project: project}}, socket) do
    send_update(Grav1Web.ProjectLogComponent,
      id: "#{Grav1Web.ProjectLogComponent}:#{project.id}",
      log: project.log
    )

    {:noreply, socket}
  end

  # update only project segments
  def handle_info(
        %{
          topic: @topic,
          event: "update_segments",
          payload: %{project: project, workers: workers}
        },
        socket
      ) do
    send_update(Grav1Web.ProjectSegmentsComponent,
      id: "#{Grav1Web.ProjectSegmentsComponent}:#{project.id}",
      segments: get_segments(project, workers)
    )

    {:noreply, socket}
  end

  def get_segments(project, workers) do
    case project.segments do
      %Ecto.Association.NotLoaded{} ->
        []

      segments ->
        workers =
          workers
          |> Enum.filter(fn worker -> worker.segment in Map.keys(segments) end)
          |> Enum.map(fn worker -> {worker.segment, {worker.progress_num, worker.pass}} end)
          |> Map.new()

        verifying =
          Grav1.VerificationExecutor.get_queue()
          |> Enum.map(fn job -> job.segment.id end)

        segments
        |> Enum.map(fn {k, segment} ->
          {progress, pass} =
            if segment.filesize == 0 do
              Map.get(workers, k, {0, 0})
            else
              {nil, nil}
            end

          %{
            n: segment.n,
            pass: pass,
            progress: progress,
            frames: segment.frames,
            filesize: segment.filesize,
            verifying: segment.id in verifying
          }
        end)
        |> Enum.sort_by(& &1.n)
    end
  end

  def get_segments(projects) do
    get_segments(projects, Grav1.WorkerAgent.get_workers())
  end

  # update project list and project
  def update(project, ratelimit \\ false) do
    if not ratelimit or RateLimit.can_execute?("projects", 1 / 10) do
      Endpoint.broadcast(@topic, "update", %{
        project: project,
        projects: true
      })
    end
  end

  # update only project
  def update_project(project, ratelimit \\ false) do
    if not ratelimit or RateLimit.can_execute?("project:#{project.id}", 1 / 10) do
      Endpoint.broadcast(@topic, "update_project", %{project: project})
    end
  end

  # update only log of project
  def update_log(project) do
    Endpoint.broadcast(@topic, "log", %{
      project: project
    })
  end

  # update only segments of project
  def update_segments(project, ratelimit \\ false) do
    if not ratelimit or RateLimit.can_execute?("project_segments:#{project.id}", 1 / 10) do
      Grav1Web.Endpoint.broadcast(@topic, "update_segments", %{
        project: project,
        workers: Grav1.WorkerAgent.get_workers()
      })
    end
  end

  # update only project list
  def update() do
    Grav1Web.Endpoint.broadcast(@topic, "update_projects", %{projects: Projects.get_projects()})
  end
end
