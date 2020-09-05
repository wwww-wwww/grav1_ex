defmodule Grav1Web.ProjectsLive do
  use Phoenix.LiveView

  @topic "projects_live"

  alias Grav1.{Projects, Project, Repo}

  def render(assigns) do
    Grav1Web.PageView.render("projects.html", assigns)
  end

  def get_projects() do
    Projects.get_projects()
  end

  def mount(_, _, socket) do
    if connected?(socket), do: Grav1Web.Endpoint.subscribe(@topic)

    new_socket =
      socket
      |> assign(projects: get_projects())
      |> assign(project_changeset: Project.changeset(%Project{}))
      |> assign(page: nil)

    {:ok, new_socket}
  end

  def handle_event(
        "add_project",
        %{"files" => files, "encoder" => encoder, "encoder_params" => encoder_params},
        socket
      ) do
    case Projects.add_project(files, encoder, encoder_params) do
      {:error, reason} ->
        {:reply, %{success: false, reason: reason}, socket}

      _ ->
        {:reply, %{success: true}, socket}
    end
  end

  def handle_event("view_project", %{"id" => id}, socket) do
    case Repo.get(Project, id) do
      nil ->
        {:noreply, socket |> assign(page: nil)}

      project ->
        new_socket =
          socket
          |> assign(
            page:
              {live_component(socket, Grav1Web.ProjectComponent,
                 id: "project:#{project.id}",
                 project: project
               ), :project}
          )

        {:noreply, new_socket}
    end
  end

  def handle_info(%{topic: @topic, payload: %{project: project, projects: projects}}, socket) do
    send_update(Grav1Web.ProjectComponent, id: "project:#{project.id}")
    {:noreply, socket |> assign(projects: projects)}
  end

  def handle_info(%{topic: @topic, payload: %{projects: projects}}, socket) do
    {:noreply, socket |> assign(projects: projects)}
  end

  def update(project) do
    Grav1Web.Endpoint.broadcast(@topic, "projects:update", %{
      project: project,
      projects: get_projects()
    })
  end

  def update() do
    Grav1Web.Endpoint.broadcast(@topic, "projects:update", %{projects: get_projects()})
  end
end
