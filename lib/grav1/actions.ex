defmodule Grav1.Actions do
  use GenServer

  alias Grav1.{ActionsQueue, Projects}

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    {:ok, state}
  end

  def run(%{project: project, action: action, params: params}) do
    output =
      Application.fetch_env!(:grav1, :path_projects)
      |> Path.join(to_string(project.id))
      |> Path.join("completed.mkv")

    args =
      [
        "-u",
        action,
        to_string(project.id),
        project.input,
        output
      ]
      |> Enum.concat(params)

    Projects.log(project, "Running #{action} " <> Enum.join(args, " "))

    Port.open(
      {:spawn_executable, Grav1.get_path(:python)},
      [:stderr_to_stdout, :binary, :exit_status, :line, args: args]
    )
    |> Grav1.Split.stream_port(0, fn line, _acc ->
      Projects.log(project, line)
    end)
    |> case do
      resp ->
        Projects.log(project, "#{action} exited: #{elem(resp, 0)}")
    end
  end

  def add(project, action, params \\ []) do
    if project != nil and action in get() do
      GenServer.call(
        ActionsQueue,
        {:push,
         %{
           project: project,
           action: action,
           params: params
         }}
      )

      GenServer.cast(__MODULE__, :loop)
    end
  end

  def get_queue() do
    GenServer.call(ActionsQueue, :get)
  end

  def handle_cast(:loop, state) do
    if (job = GenServer.call(ActionsQueue, :pop)) != :empty do
      run(job)
      GenServer.call(ActionsQueue, {:remove, job})
      GenServer.cast(__MODULE__, :loop)
    end

    {:noreply, state}
  end

  def get() do
    Application.fetch_env!(:on_complete_actions, :actions)
  end

  def reload() do
    case File.ls("actions") do
      {:ok, files} ->
        files = Enum.map(files, &Path.join("actions", &1))
        Application.put_env(:on_complete_actions, :actions, files)

      _ ->
        Application.put_env(:on_complete_actions, :actions, [])
    end
  end
end

defmodule Grav1.ActionsQueue do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, {:queue.new(), []}, name: __MODULE__)
  end

  def init(state) do
    case File.mkdir_p(Application.fetch_env!(:grav1, :path_verification)) do
      :ok ->
        {:ok, state}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  def handle_call(:get, _, {queue, last}) do
    {:reply, List.flatten(Tuple.to_list(queue)) ++ last, {queue, last}}
  end

  def handle_call(:pop, _, {queue, last}) do
    case :queue.out(queue) do
      {{:value, item}, tail} ->
        {:reply, item, {tail, last ++ [item]}}

      {:empty, tail} ->
        {:reply, :empty, {tail, last}}
    end
  end

  def handle_call({:push, item}, _, {queue, last}) do
    {:reply, :ok, {:queue.in(item, queue), last}}
  end

  def handle_call({:remove, item}, _, {queue, last}) do
    if item in last do
      {:reply, :ok, {queue, List.delete(last, item)}}
    else
      {:reply, :ok, {queue, last}}
    end
  end
end
