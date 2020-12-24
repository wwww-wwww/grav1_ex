defmodule Grav1Web.WorkersLive do
  use Grav1Web, :live_view

  @topic "clients_live"

  def render(assigns) do
    Grav1Web.PageView.render("workers.html", assigns)
  end

  def get_workers(clients) do
    {workers, max_workers} =
      clients
      |> Enum.filter(&elem(&1, 1).meta.connected)
      |> Enum.reduce({[], 0}, fn {_, client}, {workers, num_workers} ->
        {workers ++ client.state.workers, num_workers + client.state.max_workers}
      end)

    %{workers: workers, max_workers: max_workers}
  end

  def mount(_, session, socket) do
    if connected?(socket), do: Grav1Web.Endpoint.subscribe(@topic)

    socket =
      socket
      |> assign(get_workers(Grav1.WorkerAgent.get()))
      |> assign(user: Grav1.Guardian.user(session))

    {:ok, socket}
  end

  def handle_info(%{topic: @topic, payload: clients}, socket) do
    {:noreply, socket |> assign(get_workers(clients))}
  end

  def update(new_clients) do
    Grav1Web.Endpoint.broadcast(@topic, "workers:update", new_clients)
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
    |> Enum.map(&{elem(Integer.parse(elem(&1, 0)), 0), elem(&1, 1)})
    |> Enum.sort()
    |> Enum.group_by(&elem(&1, 1).meta.user)
  end

  def mount(_, session, socket) do
    if connected?(socket), do: Grav1Web.Endpoint.subscribe(@topic)

    socket =
      socket
      |> assign(user: Grav1.Guardian.user(session))
      |> assign(clients: get_clients())

    {:ok, socket}
  end

  def handle_info(%{topic: @topic, payload: clients}, socket) do
    {:noreply, socket |> assign(clients: group_clients(clients))}
  end
end
