defmodule Grav1Web.PageController do
  use Grav1Web, :controller

  import Phoenix.LiveView.Controller

  def index(conn, _params) do
    render(conn, "index.html", layout: false)
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
