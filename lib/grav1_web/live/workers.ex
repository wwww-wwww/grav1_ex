defmodule Grav1Web.WorkersLive do
  use Phoenix.LiveView

  @topic "workers_live"

  def render(assigns) do
    Grav1Web.PageView.render("workers.html", assigns)
  end

  def get_clients() do
    Grav1.WorkerAgent.get()
  end

  def mount(_, _, socket) do
    if connected?(socket), do: Grav1Web.Endpoint.subscribe(@topic)
    {:ok, socket |> assign(clients: get_clients())}
  end

  def handle_info(%{topic: @topic, payload: %{clients: clients}}, socket) do
    {:noreply, socket |> assign(clients: clients)}
  end

  def update(new_clients) do
    Grav1Web.Endpoint.broadcast(@topic, "workers:update", %{clients: new_clients})
  end
end
