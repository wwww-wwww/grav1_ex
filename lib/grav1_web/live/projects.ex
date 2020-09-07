defmodule Grav1Web.ProjectsLive do
  use Phoenix.LiveView

  @topic "projects_live"

  alias Grav1.{Projects, Project, Repo}

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
                id: "project_log:#{project.id}",
                segments: project.segments
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
            "priority" => priority
          }
        },
        socket
      ) do
    case Projects.add_project(files, %{
           encoder: encoder,
           encoder_params: encoder_params,
           split_min_frames: min_frames,
           split_max_frames: max_frames,
           name: name,
           priority: priority
         }) do
      {:error, reason} ->
        {:reply, %{success: false, reason: reason}, socket}

      _ ->
        {:reply, %{success: true}, socket}
    end
  end

  def handle_event("view_log", %{"id" => id}, socket) do
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
                 live_component(socket, Grav1Web.ProjectLogComponent,
                   id: "project_log:#{project.id}",
                   log: project.log
                 )
             )
         )}
    end
  end

  def handle_event("view_project", %{"id" => id}, socket) do
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
               a: 5,
               page:
                 live_component(socket, Grav1Web.ProjectSegmentsComponent,
                   id: "project_segments:#{project.id}",
                   segments: project.segments
                 )
             )
         )}
    end
  end

  # update project list and project
  def handle_info(%{topic: @topic, payload: %{project: project, projects: projects}}, socket) do
    send_update(Grav1Web.ProjectComponent, id: "project:#{project.id}", project: project)
    {:noreply, socket |> assign(projects: projects)}
  end

  # update only project list
  def handle_info(%{topic: @topic, payload: %{projects: projects}}, socket) do
    {:noreply, socket |> assign(projects: projects)}
  end

  # update only project
  def handle_info(%{topic: @topic, payload: %{project: project}}, socket) do
    send_update(Grav1Web.ProjectComponent, id: "project:#{project.id}", project: project)
    {:noreply, socket}
  end

  # update only project logs
  def handle_info(%{topic: @topic, payload: %{projectid: projectid, log: log}}, socket) do
    send_update(Grav1Web.ProjectLogComponent, id: "project_log:#{projectid}", log: log)
    {:noreply, socket}
  end

  # update only project segments
  def handle_info(%{topic: @topic, payload: %{projectid: projectid, segments: segments}}, socket) do
    send_update(Grav1Web.ProjectSegmentComponent,
      id: "project_segments:#{projectid}",
      segments: segments
    )

    {:noreply, socket}
  end

  # update project list and project
  def update(project, ratelimit \\ false) do
    if not ratelimit or Grav1.RateLimit.can_execute?("projects", 1 / 10) do
      Grav1Web.Endpoint.broadcast(@topic, "projects:update", %{
        project: project,
        projects: Projects.get_projects()
      })
    end
  end

  # update only project
  def update_project(project, ratelimit \\ false) do
    if not ratelimit or Grav1.RateLimit.can_execute?("project:#{project.id}", 1 / 10) do
      Grav1Web.Endpoint.broadcast(@topic, "projects:update", %{project: project})
    end
  end

  # update only log of project
  def update_log(project) do
    Grav1Web.Endpoint.broadcast(@topic, "projects:update", %{
      projectid: project.id,
      log: project.log
    })
  end

  # update only segments of project
  def update_segments(project) do
    Grav1Web.Endpoint.broadcast(@topic, "projects:update", %{
      projectid: project.id,
      segments: project.segments
    })
  end

  # update only project list
  def update() do
    Grav1Web.Endpoint.broadcast(@topic, "projects:update", %{projects: Projects.get_projects()})
  end
end
