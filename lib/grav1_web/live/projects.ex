defmodule Grav1Web.ProjectsLive do
  use Grav1Web, :live_view

  @topic "projects_live"

  alias Grav1.{Projects, Project, RateLimit, Repo, WorkerAgent, User}
  alias Grav1Web.Endpoint

  def render(assigns) do
    Grav1Web.PageView.render("projects.html", assigns)
  end

  def mount(params = %{"id" => id}, session, socket) do
    case Projects.get_project(id) do
      nil ->
        mount(%{}, session, socket)

      project ->
        page =
          live_component(socket, Grav1Web.ProjectPageComponent,
            id: "project:#{project.id}",
            project: project,
            page:
              live_component(socket, Grav1Web.ProjectSegmentsComponent,
                id: "#{Grav1Web.ProjectSegmentsComponent}:#{project.id}",
                segments: get_segments(project)
              )
          )

        mount(params, session, socket, page)
    end
  end

  def mount(_, session, socket, page \\ nil) do
    if connected?(socket), do: Grav1Web.Endpoint.subscribe(@topic)

    socket =
      socket
      |> assign(user: Grav1.Guardian.user(session))
      |> assign(projects: Projects.get_projects())
      |> assign(project_changeset: Project.changeset(%Project{}))
      |> assign(page: page)
      |> assign(encoder_params: Grav1.Encoder.params())
      |> assign(encoder_params_json: Grav1.Encoder.params_json())

    {:ok, socket, temporary_assigns: [encoder_params: %{}, encoder_params_json: ""]}
  end

  def handle_params(_, _, socket) do
    {:noreply, socket}
  end

  def handle_event("add_project", %{"files" => files, "params" => params}, socket) do
    case User.has_permissions(socket) do
      :yes ->
        case Projects.add_project(files, params) do
          {:error, reason} ->
            {:reply, %{success: false, reason: reason}, socket}

          _ ->
            {:reply, %{success: true}, socket}
        end

      reason ->
        {:reply, %{success: false, reason: reason}, socket}
    end
  end

  def handle_event("view_project", %{"id" => id}, socket) do
    view_project_page(socket, id, fn project ->
      case get_segments(project) do
        [] ->
          {Grav1Web.ProjectLogComponent, [log: project.log]}

        segments ->
          {Grav1Web.ProjectSegmentsComponent, [segments: segments]}
      end
    end)
  end

  def handle_event("view_project_segments", _, socket) do
    view_project_page(socket, socket.assigns.page.assigns.project.id, fn project ->
      {Grav1Web.ProjectSegmentsComponent, [segments: get_segments(project)]}
    end)
  end

  def handle_event("view_project_log", _, socket) do
    view_project_page(socket, socket.assigns.page.assigns.project.id, fn project ->
      {Grav1Web.ProjectLogComponent, [log: project.log]}
    end)
  end

  def handle_event("view_project_settings", _, socket) do
    view_project_page(socket, socket.assigns.page.assigns.project.id, fn project ->
      {Grav1Web.ProjectSettingsComponent, [project: project]}
    end)
  end

  def handle_event(
        "run_complete_action",
        %{"action" => action, "params" => params},
        socket
      ) do
    case User.has_permissions(socket) do
      :yes ->
        Grav1.Actions.add(socket.assigns.page.assigns.project, action, params)
        {:reply, %{success: true}, socket}

      reason ->
        {:reply, %{success: false, reason: reason}, socket}
    end
  end

  def handle_event("start_project", _, socket) do
    case User.has_permissions(socket) do
      :yes ->
        Projects.start_project(socket.assigns.page.assigns.project)
        {:reply, %{success: true}, socket}

      reason ->
        {:reply, %{success: false, reason: reason}, socket}
    end
  end

  def handle_event("stop_project", _, socket) do
    case User.has_permissions(socket) do
      :yes ->
        Projects.stop_project(socket.assigns.page.assigns.project)
        {:reply, %{success: true}, socket}

      reason ->
        {:reply, %{success: false, reason: reason}, socket}
    end
  end

  def handle_event("reset_project", %{"encoder_params" => params}, socket) do
    case User.has_permissions(socket) do
      :yes ->
        project = socket.assigns.page.assigns.project

        case Projects.reset_project(project, params) do
          :ok ->
            {:reply, %{success: true}, socket}

          {:error, reason} ->
            {:reply, %{success: false, reason: reason}, socket}

          err ->
            {:reply, %{success: false, reason: inspect(err)}, socket}
        end

      reason ->
        {:reply, %{success: false, reason: reason}, socket}
    end
  end

  # update project list and project
  def handle_info(
        %{topic: @topic, event: "update", payload: %{project: project, projects: true}},
        socket
      ) do
    send_update(Grav1Web.ProjectComponent,
      id: "#{Grav1Web.ProjectComponent}:#{project.id}",
      project: project
    )

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
  def handle_info(
        %{topic: @topic, event: "update_project", payload: %{project: project}},
        socket
      ) do
    send_update(Grav1Web.ProjectComponent,
      id: "#{Grav1Web.ProjectComponent}:#{project.id}",
      project: project
    )

    send_update(Grav1Web.ProjectSettingsComponent,
      id: "#{Grav1Web.ProjectSettingsComponent}:#{project.id}",
      project: project
    )

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
          payload: %{project: project, segments: segments}
        },
        socket
      ) do
    send_update(Grav1Web.ProjectSegmentsComponent,
      id: "#{Grav1Web.ProjectSegmentsComponent}:#{project.id}",
      segments: segments,
      update_action: :append
    )

    {:noreply, socket}
  end

  def view_project_page(socket, id, assign) do
    case Projects.get_project(id) do
      nil ->
        {:noreply, socket |> assign(page: nil)}

      project ->
        {page, assigns} = assign.(project)

        new_socket =
          socket
          |> push_patch(to: "/projects/#{id}")
          |> assign(
            page:
              live_component(socket, Grav1Web.ProjectPageComponent,
                id: "project:#{project.id}",
                project: project,
                page: live_component(socket, page, [id: "#{page}:#{project.id}"] ++ assigns)
              )
          )

        {:noreply, new_socket}
    end
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
            id: segment.id,
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

  def map_changed_segments(segments) do
    verifying =
      Grav1.VerificationExecutor.get_queue()
      |> Enum.map(fn job -> job.segment.id end)

    segments
    |> Enum.map(fn {segment, workers} ->
      {progress, pass} =
        if length(workers) > 0 and segment.filesize == 0 do
          workers
          |> Enum.map(&{&1.progress_num, &1.pass})
          |> Enum.at(0)
        else
          {nil, nil}
        end

      %{
        id: segment.id,
        n: segment.n,
        pass: pass,
        progress: progress,
        frames: segment.frames,
        filesize: segment.filesize,
        verifying: segment.id in verifying
      }
    end)
  end

  def get_segments(project) do
    get_segments(project, WorkerAgent.get_workers())
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
  def update_segments(project, changed_segments) do
    Grav1Web.Endpoint.broadcast(@topic, "update_segments", %{
      project: project,
      segments: map_changed_segments(changed_segments)
    })
  end

  # update only project list
  def update() do
    Grav1Web.Endpoint.broadcast(@topic, "update_projects", %{projects: Projects.get_projects()})
  end
end
