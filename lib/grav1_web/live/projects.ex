defmodule Grav1Web.ProjectsLive do
  use Phoenix.LiveView
  
  @topic "projects_live"

  alias Grav1.{Projects, Project}

  def render(assigns) do
    Grav1Web.LiveView.render("projects.html", assigns)
  end

  def get_projects() do
    Projects.get_projects()
  end
  
  def mount(_, _, socket) do
    if connected?(socket), do: Grav1Web.Endpoint.subscribe(@topic)
    {:ok, socket
    |> assign(projects: get_projects())
    |> assign(project_changeset: Project.changeset(%Project{}))}
  end

  def handle_info(%{topic: @topic, payload: %{projects: projects}}, socket) do
    {:noreply, socket |> assign(projects: projects)}
  end

  def update() do
    Grav1Web.Endpoint.broadcast(@topic, "projects:update", %{projects: get_projects()})
  end
end
