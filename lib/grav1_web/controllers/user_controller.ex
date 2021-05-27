defmodule Grav1Web.UserController do
  use Grav1Web, :controller

  alias Grav1.{Guardian, Repo, User}

  def sign_up(conn, %{"user" => user}) do
    changeset = User.changeset(%User{}, user)

    case Repo.insert(changeset) do
      {:ok, user} ->
        conn
        |> Guardian.Plug.sign_in(user)
        |> redirect(to: Routes.page_path(conn, :index))

      {:error, changeset} ->
        {field, error} =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
            Enum.reduce(opts, msg, fn {key, value}, acc ->
              String.replace(acc, "%{#{key}}", to_string(value))
            end)
          end)
          |> Enum.at(0)

        conn
        |> put_flash(:error, "#{field} #{error}")
        |> redirect(to: Routes.user_path(conn, :sign_up))
    end
  end

  def sign_in(conn, %{"user" => %{"username" => username, "password" => password}}) do
    case Repo.get(User, username |> to_string() |> String.downcase()) do
      nil ->
        conn
        |> put_flash(:error, "Incorrect username or password")
        |> redirect(to: Routes.user_path(conn, :sign_in))

      user ->
        if Argon2.verify_pass(password |> to_string(), user.password) do
          conn
          |> Guardian.Plug.sign_in(user)
          |> redirect(to: Routes.page_path(conn, :index))
        else
          conn
          |> put_flash(:error, "Incorrect username or password")
          |> redirect(to: Routes.user_path(conn, :sign_in))
        end
    end
  end

  def sign_out(conn, _) do
    conn
    |> Guardian.Plug.sign_out()
    |> redirect(to: Routes.page_path(conn, :index))
  end

  def auth(conn, %{"key" => key}) do
    case Repo.get_by(User, key: key) do
      nil ->
        conn
        |> put_status(200)
        |> json(%{success: false, reason: "bad key"})

      user ->
        token =
          conn
          |> Guardian.Plug.sign_in(user)
          |> Guardian.Plug.current_token()

        conn
        |> put_status(200)
        |> json(%{success: true, token: token})
    end
  end

  def auth(conn, %{"username" => username, "password" => password}) do
    case Repo.get_by(User, username: username |> to_string() |> String.downcase()) do
      nil ->
        conn
        |> put_status(200)
        |> json(%{success: false, reason: "bad username or password"})

      user ->
        if Argon2.verify_pass(password |> to_string(), user.password) do
          token =
            conn
            |> Guardian.Plug.sign_in(user)
            |> Guardian.Plug.current_token()

          conn
          |> put_status(200)
          |> json(%{success: true, token: token})
        else
          conn
          |> put_status(200)
          |> json(%{success: false, reason: "bad username or password"})
        end
    end
  end
end
