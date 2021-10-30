defmodule Grav1Web.LayoutView do
  use Grav1Web, :view

  alias Grav1.Guardian

  def logged_in?(conn) do
    conn |> Map.has_key?(:user) or
      (Guardian.Plug.authenticated?(conn) and Guardian.Plug.current_resource(conn) != nil)
  end

  def title(conn) do
    case conn do
      %{view: view} -> view
      _ -> action_name(conn)
    end
  end

  def nav_link(conn, name, page, id) do
    live_redirect(name,
      to: page.(conn, id),
      class: if(title(conn) == id, do: "header-active")
    )
  end

  def nav_link(conn, name, page) do
    live_redirect(name,
      to: Routes.live_path(conn, page),
      class: if(title(conn) == page, do: "header-active")
    )
  end
end
