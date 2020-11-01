defmodule Grav1Web.ProjectComponent do
  use Grav1Web, :live_component

  def render(assigns) do
    Grav1Web.PageView.render("project.html", assigns)
  end
end

defmodule Grav1Web.ProjectPageComponent do
  use Grav1Web, :live_component

  def render(assigns) do
    Grav1Web.PageView.render("project_page.html", assigns)
  end
end

defmodule Grav1Web.ProjectLogComponent do
  use Grav1Web, :live_component

  def render(assigns) do
    Grav1Web.PageView.render("project_log.html", assigns)
  end
end

defmodule Grav1Web.ProjectSegmentsComponent do
  use Grav1Web, :live_component

  def render(assigns) do
    Grav1Web.PageView.render("project_segments.html", assigns)
  end

  def mount(socket) do
    {:ok, socket |> assign(:update_action, :replace)}
  end
end

defmodule Grav1Web.ProjectSettingsComponent do
  use Grav1Web, :live_component

  def render(assigns) do
    Grav1Web.PageView.render("project_settings.html", assigns)
  end
end
