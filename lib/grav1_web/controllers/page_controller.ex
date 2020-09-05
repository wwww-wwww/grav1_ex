defmodule Grav1Web.PageController do
  use Grav1Web, :controller

  import Phoenix.LiveView.Controller

  alias Grav1.User

  def index(conn, _params) do
    render(conn, "index.html")
  end

  def workers(conn, _params) do
    live_render(conn, Grav1Web.WorkersLive)
  end

  def sign_up(conn, _) do
    conn
    |> put_view(Grav1Web.UserView)
    |> live_render(Grav1Web.SignUpLive)
  end

  def sign_in(conn, _) do
    conn
    |> put_view(Grav1Web.UserView)
    |> live_render(Grav1Web.SignInLive)
  end
end
