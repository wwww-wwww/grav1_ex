defmodule Grav1Web.PageView do
  use Grav1Web, :view

  alias Grav1.Guardian
  
  alias Phoenix.HTML.{Tag, Form}

  def logged_in?(conn) do
    Guardian.Plug.authenticated?(conn) and Guardian.Plug.current_resource(conn) != nil
  end

end
