defmodule Grav1Web.SignInLive do
  use Phoenix.LiveView

  def render(assigns) do
    Grav1Web.UserView.render("sign_in.html", assigns)
  end

  def handle_params(_, _, socket) do
    {:noreply, socket}
  end
end

defmodule Grav1Web.SignUpLive do
  use Phoenix.LiveView

  alias Grav1.User

  def render(assigns) do
    changeset = User.changeset(%User{})
    Grav1Web.UserView.render("sign_up.html", Map.put(assigns, :changeset, changeset))
  end

  def handle_params(_, _, socket) do
    {:noreply, socket}
  end
end

defmodule Grav1Web.UserLive do
  use Phoenix.LiveView

  def render(assigns) do
    Grav1Web.UserView.render("user.html", assigns)
  end

  def mount(_, session, socket) do
    case Grav1.Guardian.resource_from_claims(session) do
      {:ok, user} ->
        {:ok, socket |> assign(user: user)}

      _ ->
        {:ok, socket |> put_flash(:error, "bad resource") |> redirect(to: "/")}
    end
  end

  def handle_params(_, _, socket) do
    {:noreply, socket}
  end
end
