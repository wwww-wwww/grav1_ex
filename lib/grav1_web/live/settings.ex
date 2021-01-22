defmodule Grav1Web.SettingsLive do
  use Grav1Web, :live_view

  @topic "settings_live"

  alias Grav1Web.Endpoint

  def render(assigns) do
    Grav1Web.PageView.render("settings.html", assigns)
  end

  def mount(_, session, socket) do
    if connected?(socket), do: Grav1Web.Endpoint.subscribe(@topic)

    socket =
      socket
      |> assign(user: Grav1.Guardian.user(session))
      |> assign(actions: Grav1.Actions.get())
    
    {:ok, socket}
  end

  def handle_params(_, _, socket) do
    {:noreply, socket}
  end

  def handle_event("reload_actions", %{}, socket) do
    Grav1.Actions.reload()
    Endpoint.broadcast(@topic, "reload_actions", %{})
    {:reply, %{success: true}, socket}
  end

  def handle_info(%{topic: @topic, event: "reload_actions"}, socket) do
    {:noreply, assign(socket, actions: Grav1.Actions.get())}
  end
end
