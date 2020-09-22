defmodule Grav1Web.ProjectComponent do
  use Phoenix.LiveComponent

  def render(assigns) do
    Grav1Web.PageView.render("project.html", assigns)
  end
end

defmodule Grav1Web.ProjectLogComponent do
  use Phoenix.LiveComponent

  def render(assigns) do
    Grav1Web.PageView.render("project_log.html", assigns)
  end
end

defmodule Grav1Web.ProjectSegmentsComponent do
  use Phoenix.LiveComponent

  def render(assigns) do
    Grav1Web.PageView.render("project_segments.html", assigns)
  end
end

defmodule Grav1Web.ProjectSettingsComponent do
  use Phoenix.LiveComponent

  def render(assigns) do
    Grav1Web.PageView.render("project_settings.html", assigns)
  end
end
