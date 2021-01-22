defmodule Grav1.AuthErrorHandler do
  import Plug.Conn

  def auth_error(conn, {type, _reason}, _opts) do
    body = Jason.encode!(%{error: to_string(type)})

    conn
    |> Phoenix.Controller.put_flash(:info, "You must be logged in to do this")
    |> Phoenix.Controller.redirect(to: "/sign_in")
  end
end
