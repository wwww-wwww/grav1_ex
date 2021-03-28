defmodule Grav1.Worker do
  defstruct progress_num: 0,
            progress_den: 0,
            pass: 1,
            segment: nil,
            project: nil
end

defmodule Grav1.ClientMeta do
  defstruct socket_id: nil,
            name: "",
            user: "",
            connected: true,
            timeout: nil,
            platform: nil,
            uuid: ""
end

defmodule Grav1.ClientState do
  defstruct workers: [],
            max_workers: 0,
            job_queue: [],
            queue_size: 0,
            upload_queue: [],
            downloading: nil,
            uploading: [],
            weighted_workers: nil
end

defmodule Grav1.Client do
  defstruct meta: %Grav1.ClientMeta{},
            state: %Grav1.ClientState{},
            sending: %{
              downloading: nil,
              max_workers: nil
            }
end

defmodule Grav1.WorkerAgent do
  use GenServer

  import Ecto.UUID, only: [generate: 0]

  alias Grav1.{Client, Projects, Worker}

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__, hibernate_after: 1_000)
  end

  def init(state) do
    {:ok, state}
  end

  def handle_call(:get, _, clients) do
    {:reply, clients, clients}
  end

  def handle_call({:connect, socket, state, meta}, _, clients) do
    client = new_client(socket, state, meta)
    new_clients = Map.put(clients, socket.assigns.socket_id, client)

    {:reply, client, new_clients}
  end

  # reconnect
  def handle_call({:connect, socket, state, meta, socket_id, uuid}, _, clients) do
    {new_client, new_clients} =
      case Map.get(clients, socket_id) do
        nil ->
          new_client = new_client(socket, state, meta)
          {new_client, Map.put(clients, socket.assigns.socket_id, new_client)}

        client ->
          if client.meta.user == socket.assigns.user_id and
               client.meta.uuid == uuid do
            if client.meta.timeout != nil do
              Process.cancel_timer(client.meta.timeout)
            end

            new_client =
              %{
                client
                | meta: %{
                    client.meta
                    | socket_id: socket.assigns.socket_id,
                      connected: true,
                      uuid: generate(),
                      timeout: nil
                  }
              }
              |> struct(state)

            {
              new_client,
              clients
              |> Map.delete(socket_id)
              |> Map.put(socket.assigns.socket_id, new_client)
            }
          else
            new_client = new_client(socket, state, meta)
            {new_client, Map.put(clients, socket.assigns.socket_id, new_client)}
          end
      end

    {:reply, new_client, new_clients}
  end

  def handle_call({:update_clients, socket_ids, opts}, _, clients) do
    new_clients =
      socket_ids
      |> Enum.reduce(clients, fn socket_id, acc ->
        set_clients(acc, to_string(socket_id), opts)
      end)

    {:reply, new_clients, new_clients}
  end

  def handle_call(:get_workers, _, clients) do
    workers =
      Enum.reduce(clients, [], fn {_, client}, acc ->
        acc ++ client.state.workers
      end)

    {:reply, workers, clients}
  end

  def handle_call(:distribute_segments, _, clients) do
    {clients_segments, new_clients} =
      case distribute_segments(clients) do
        nil ->
          {nil, clients}

        {clients_segments, new_clients} ->
          new_clients = Map.merge(clients, new_clients)
          {clients_segments, new_clients}
      end

    {:reply, {clients_segments, new_clients}, new_clients}
  end

  def handle_call({:update_workers, id, workers}, _, clients) do
    case Map.get(clients, id) do
      nil ->
        {:reply, clients, clients}

      client ->
        new_clients =
          clients
          |> Map.put(id, %{client | state: %{client.state | workers: workers}})

        {:reply, new_clients, new_clients}
    end
  end

  def handle_call({:get_client, socket_id}, _, clients) do
    {:reply, Map.get(clients, to_string(socket_id)), clients}
  end

  def handle_call({:get_clients, username, name}, _, clients) do
    filtered =
      :maps.filter(
        fn _, client ->
          client.meta.user == username and
            client.meta.name == name
        end,
        clients
      )

    {:reply, filtered, clients}
  end

  def handle_info({:remove, socket_id}, clients) do
    new_clients = Map.delete(clients, socket_id)
    Grav1Web.WorkersLive.update(new_clients)
    {:noreply, new_clients}
  end

  def connect(socket, state, meta) do
    {state, meta} = map_client(state, meta)

    {:ok, GenServer.call(__MODULE__, {:connect, socket, state, meta})}
  end

  # reconnect
  def connect(socket, state, meta, socket_id, uuid) do
    {state, meta} = map_client(state, meta)

    {:ok, GenServer.call(__MODULE__, {:connect, socket, state, meta, socket_id, uuid})}
  end

  def disconnect(socket) do
    timer = Process.send_after(__MODULE__, {:remove, socket.assigns.socket_id}, 30000)
    update_client(socket.assigns.socket_id, meta: %{connected: false, timeout: timer})
  end

  def remove(socket_id) do
    GenServer.call(__MODULE__, {:remove, socket_id})
    |> Grav1Web.WorkersLive.update()
  end

  def get() do
    GenServer.call(__MODULE__, :get)
  end

  def get_workers() do
    GenServer.call(__MODULE__, :get_workers)
  end

  defp distribute_segments(clients) do
    available_clients =
      :maps.filter(
        fn _, client ->
          client.sending.downloading == nil and client.meta.connected and
            client.state.downloading == nil and client.state.max_workers > 0 and
            (length(client.state.job_queue) < client.state.queue_size or
               (length(client.state.job_queue) == 0 and
                  ((client.state.weighted_workers == nil and
                      length(client.state.workers) < client.state.max_workers) or
                     (client.state.weighted_workers != nil and
                        client.state.weighted_workers < client.state.max_workers))))
        end,
        clients
      )

    if map_size(available_clients) > 0 do
      verifying_segments =
        Grav1.VerificationExecutor.get_queue()
        |> Enum.map(fn job ->
          job.segment.id
        end)

      segments = Projects.get_segments(clients, verifying_segments)

      {clients_segments, _} =
        Enum.reduce(available_clients, {[], segments}, fn {key, client}, {acc, segments} ->
          segments
          |> Enum.filter(fn segment ->
            segment.id != client.state.downloading and
              segment.id not in client.state.job_queue and
              segment.id not in client.state.upload_queue and
              segment.id not in client.state.uploading and
              segment.id not in Enum.map(client.state.workers, & &1.segment)
          end)
          |> List.first()
          |> case do
            nil ->
              {acc, segments}

            new_segment ->
              new_segments =
                segments
                |> Enum.filter(fn segment -> segment.id != new_segment.id end)

              {acc ++ [{{key, client}, new_segment}], new_segments}
          end
        end)

      new_clients =
        clients_segments
        |> Enum.reduce(%{}, fn {{key, client}, segment}, acc ->
          Map.put(acc, key, %{client | sending: %{client.sending | downloading: segment.id}})
        end)

      clients_segments
      |> Enum.each(fn {{_, client}, segment} ->
        Grav1Web.WorkerChannel.push_segment(client.meta.socket_id, segment)
      end)

      {clients_segments, new_clients}
    else
      nil
    end
  end

  def distribute_segments() do
    {clients_segments, new_clients} = GenServer.call(__MODULE__, :distribute_segments)

    if clients_segments != nil and length(clients_segments) > 0 do
      Grav1Web.WorkersLive.update(new_clients)
    end
  end

  def cancel_segments(segments) do
    get()
    |> (&:maps.filter(fn _, v -> v.meta.connected end, &1)).()
    |> Enum.reduce([], fn {socket_id, client}, acc ->
      client.state.workers
      |> Enum.reduce([], fn worker, acc ->
        if worker.segment not in segments do
          acc ++ [worker.segment]
        else
          acc
        end
      end)
      |> Enum.concat(
        Enum.filter(
          client.state.job_queue ++ [client.sending.downloading, client.state.downloading],
          fn segment ->
            segment not in segments and segment != nil
          end
        )
      )
      |> case do
        [] -> acc
        workers_segments -> acc ++ [{socket_id, workers_segments}]
      end
    end)
    |> Enum.each(fn {socket_id, segments} ->
      Grav1Web.WorkerChannel.cancel_segments(socket_id, segments)
    end)
  end

  defp set_clients(clients, id, opts) do
    case Map.get(clients, id) do
      nil ->
        clients

      client ->
        client =
          opts
          |> Enum.reduce(client, fn {key, vars}, acc ->
            Map.put(acc, key, Map.merge(Map.get(client, key), vars))
          end)

        new_sending =
          client.sending
          |> Enum.map(fn pair ->
            case pair do
              {_, nil} ->
                pair

              {:downloading, segment} ->
                if segment == client.state.downloading or
                     segment in client.state.job_queue or
                     segment in client.state.upload_queue or
                     segment in client.state.uploading do
                  {:downloading, nil}
                else
                  case Projects.get_segment(segment) do
                    nil ->
                      {:downloading, nil}

                    segment ->
                      Grav1Web.WorkerChannel.push_segment(id, segment)
                      pair
                  end
                end

              {:max_workers, n} ->
                if n == client.state.max_workers do
                  {:max_workers, nil}
                else
                  Grav1Web.WorkerChannel.push_max_workers(id, n)
                  {:max_workers, n}
                end

              _ ->
                pair
            end
          end)
          |> Map.new()

        Map.put(clients, id, %{client | sending: new_sending})
    end
  end

  def update_workers(socket_id, workers) do
    id = to_string(socket_id)

    GenServer.call(__MODULE__, {:update_workers, id, workers})
  end

  def get_client(socket_id) do
    GenServer.call(__MODULE__, {:get_client, socket_id})
  end

  def get_clients_by_name(username, name) do
    GenServer.call(__MODULE__, {:get_clients, username, name})
  end

  def update_clients(socket_ids, opts \\ []) do
    GenServer.call(__MODULE__, {:update_clients, socket_ids, opts})
    |> Grav1Web.WorkersLive.update()
  end

  def update_client(socket_id, opts \\ []) do
    update_clients([socket_id], opts)
  end

  defp new_client(socket, state, meta) do
    state = struct(%Grav1.ClientState{}, state)

    meta =
      %Grav1.ClientMeta{}
      |> struct(meta)
      |> Map.put(:user, socket.assigns.user_id)
      |> Map.put(:socket_id, socket.assigns.socket_id)
      |> Map.put(:uuid, generate())

    %Client{state: state, meta: meta}
  end

  defp map_client(state, meta) do
    new_state = for {k, v} <- state, into: %{}, do: {String.to_atom(k), v}
    new_meta = for {k, v} <- meta, into: %{}, do: {String.to_atom(k), v}

    new_workers =
      new_state.workers
      |> Enum.reduce([], fn worker, acc ->
        worker =
          worker
          |> Enum.map(fn {a, b} ->
            {String.to_atom(a), b}
          end)
          |> Map.new()

        acc ++ [struct(%Worker{}, worker)]
      end)

    {%{new_state | workers: new_workers}, new_meta}
  end
end
