defmodule Grav1Web.SignInLive do
  use Grav1Web, :live_view

  def render(assigns) do
    Grav1Web.UserView.render("sign_in.html", assigns)
  end

  def handle_params(_, _, socket) do
    {:noreply, socket}
  end
end

defmodule Grav1Web.SignUpLive do
  use Grav1Web, :live_view

  alias Grav1.User

  def render(assigns) do
    Grav1Web.UserView.render("sign_up.html", assigns)
  end

  def handle_params(_, _, socket) do
    {:noreply, socket}
  end
end

defmodule Grav1Web.UserLive do
  use Grav1Web, :live_view

  @topic "client_workers_live:"

  def render(assigns) do
    Grav1Web.UserView.render("user.html", assigns)
  end

  def mount(_, session, socket) do
    socket =
      case Grav1.Guardian.resource_from_claims(session) do
        {:ok, user} ->
          if connected?(socket), do: Grav1Web.Endpoint.subscribe("#{@topic}#{user.username}")

          socket
          |> assign(user: user)
          |> assign(clients: get_clients(user.username))

        _ ->
          socket
          |> put_flash(:error, "bad resource")
          |> redirect(to: "/")
      end

    {:ok, socket}
  end

  def get_clients(username) do
    Grav1.WorkerAgent.get()
    |> Enum.filter(fn {_, client} ->
      client.meta.user == username
    end)
  end

  def handle_info(%{topic: @topic <> _username, payload: %{clients: clients}}, socket) do
    {:noreply, socket |> assign(clients: clients)}
  end

  def handle_params(_, _, socket) do
    {:noreply, socket}
  end

  def update(username, clients) do
    Grav1Web.Endpoint.broadcast(@topic <> username, "workers:update", %{clients: clients})
  end
end

defmodule Grav1Web.UsersLive do
  use Grav1Web, :live_view

  alias Grav1.{Repo, User}

  def render(assigns) do
    Grav1Web.UserView.render("users.html", assigns)
  end

  def mount(_, session, socket) do
    users =
      Repo.all(User)
      |> Enum.sort_by(& &1.frames, :desc)

    socket =
      socket
      |> assign(user: Grav1.Guardian.user(session))
      |> assign(users: users)

    {:ok, socket}
  end

  def handle_params(_, _, socket) do
    {:noreply, socket}
  end
end
