defmodule Grav1.AuthErrorHandler do
  def auth_error(conn, {_type, _reason}, _opts) do
    conn
    |> Phoenix.Controller.put_flash(:info, "You must be logged in to do this")
    |> Phoenix.Controller.redirect(to: "/sign_in")
  end
end
