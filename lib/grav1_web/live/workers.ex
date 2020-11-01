defmodule Grav1Web.WorkersLive do
  use Grav1Web, :live_view

  @topic "workers_live"

  def render(assigns) do
    Grav1Web.PageView.render("workers.html", assigns)
  end

  def get_clients() do
    Grav1.WorkerAgent.get()
    |> get_workers()
  end

  def get_workers(clients) do
    {workers, max_workers} =
      clients
      |> Enum.filter(&elem(&1, 1).connected)
      |> Enum.reduce({[], 0}, fn {i, client}, {workers, num_workers} ->
        {workers ++ client.workers, num_workers + client.max_workers}
      end)

    %{workers: workers, max_workers: max_workers}
  end

  def mount(_, _, socket) do
    if connected?(socket), do: Grav1Web.Endpoint.subscribe(@topic)
    {:ok, socket |> assign(get_clients())}
  end

  def handle_info(%{topic: @topic, payload: assigns}, socket) do
    {:noreply, socket |> assign(assigns)}
  end

  def update(new_clients) do
    Grav1Web.Endpoint.broadcast(@topic, "workers:update", get_workers(new_clients))
  end
end

defmodule Grav1Web.ClientsLive do
  use Grav1Web, :live_view

  @topic "clients_live"

  def render(assigns) do
    Grav1Web.PageView.render("clients.html", assigns)
  end

  def get_clients() do
    Grav1.WorkerAgent.get()
    |> group_clients()
  end

  def group_clients(clients) do
    clients
    |> Enum.group_by(fn {id, client} ->
      client.user
    end)
  end

  def mount(_, _, socket) do
    if connected?(socket), do: Grav1Web.Endpoint.subscribe(@topic)
    {:ok, socket |> assign(clients: get_clients())}
  end

  def handle_info(%{topic: @topic, payload: %{clients: clients}}, socket) do
    {:noreply, socket |> assign(clients: clients)}
  end

  def update(new_clients) do
    Grav1Web.Endpoint.broadcast(@topic, "clients:update", %{clients: new_clients |> group_clients})
  end
end
