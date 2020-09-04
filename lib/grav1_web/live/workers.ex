defmodule Grav1Web.WorkersLive do
  use Phoenix.LiveView

  @topic "workers_live"

  def render(assigns) do
    Grav1Web.LiveView.render("workers.html", assigns)
  end

  def get_workers() do
    Grav1.WorkerAgent.get()
  end

  def mount(_, _, socket) do
    if connected?(socket), do: Grav1Web.Endpoint.subscribe(@topic)
    {:ok, socket |> assign(workers: get_workers())}
  end

  def handle_info(%{topic: @topic, payload: %{workers: workers}}, socket) do
    {:noreply, socket |> assign(workers: workers)}
  end

  def update() do
    Grav1Web.Endpoint.broadcast(@topic, "workers:update", %{workers: get_workers()})
  end
end
