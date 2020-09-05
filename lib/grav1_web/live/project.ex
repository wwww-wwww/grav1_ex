defmodule Grav1Web.ProjectComponent do
  use Phoenix.LiveComponent

  def render(assigns) do
    Grav1Web.PageView.render("project.html", assigns)
  end
end
