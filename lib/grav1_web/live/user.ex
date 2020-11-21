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

  alias Grav1.WorkerAgent

  @topic "clients_live"

  def render(assigns) do
    Grav1Web.UserView.render("user.html", assigns)
  end

  def mount(_, session, socket) do
    socket =
      case Grav1.Guardian.resource_from_claims(session) do
        {:ok, user} ->
          if connected?(socket), do: Grav1Web.Endpoint.subscribe(@topic)

          socket
          |> assign(user: user)
          |> assign(clients: get_clients(WorkerAgent.get(), user.username))

        _ ->
          socket
          |> put_flash(:error, "bad resource")
          |> redirect(to: "/")
      end

    {:ok, socket}
  end

  def get_clients(clients, username) do
    Enum.filter(clients, fn {_, client} ->
      client.meta.user == username
    end)
  end

  def handle_info(%{topic: @topic, payload: clients}, socket) do
    {:noreply, socket |> assign(clients: get_clients(clients, socket.assigns.user.username))}
  end

  def handle_event("set_workers", %{"socket_id" => id, "max_workers" => max_workers}, socket) do
    username = socket.assigns.user.username
    {max_workers, _} = Integer.parse(to_string(max_workers))

    case WorkerAgent.get_client(id) do
      nil ->
        {:reply, %{success: false, reason: "Client doesn't exist"}, socket}

      %{meta: %{user: ^username}} ->
        WorkerAgent.update_client(id, sending: %{max_workers: max_workers})
        {:reply, %{success: true}, socket}

      _ ->
        {:reply, %{success: false, reason: "You are not allowed to do this!"}, socket}
    end
  end

  def handle_params(_, _, socket) do
    {:noreply, socket}
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
