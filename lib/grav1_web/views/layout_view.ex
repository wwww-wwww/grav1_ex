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
end
