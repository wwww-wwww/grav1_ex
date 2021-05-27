defmodule Grav1Web.LayoutView do
  use Grav1Web, :view

  alias Grav1.Guardian

  def logged_in?(conn) do
    Guardian.Plug.authenticated?(conn) and Guardian.Plug.current_resource(conn) != nil
  end

  def title(conn, assigns) do
    cond do
      Map.has_key?(assigns, :live_module) -> assigns[:live_module]
      Map.has_key?(assigns, :view_module) -> action_name(conn)
      true -> nil
    end
  end

  def nav_link(conn, assigns, name, page, id) do
    live_redirect(name,
      to: page.(conn, id),
      class: if(title(conn, assigns) == id, do: "header-active")
    )
  end

  def nav_link(conn, assigns, name, page) do
    live_redirect(name,
      to: Routes.live_path(conn, page),
      class: if(title(conn, assigns) == page, do: "header-active")
    )
  end
end
