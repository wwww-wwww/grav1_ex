defmodule Grav1Web.LayoutView do
  use Grav1Web, :view
  
  alias Grav1.Guardian

  def logged_in?(conn) do
    Guardian.Plug.authenticated?(conn) and Guardian.Plug.current_resource(conn) != nil
  end
end
