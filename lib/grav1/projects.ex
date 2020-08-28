defmodule Grav1.Projects do
  use Agent

  alias Grav1Web.Endpoint
  
  alias Grav1.{Repo, Project, Segment}

  defstruct projects: %{}

  def start_link(_) do
    Agent.start_link(fn ->
      projects = Repo.all(Project) |> Repo.preload(:segments)
      %__MODULE__{projects: projects}
    end, name: __MODULE__)
  end

  def get_projects() do
    Agent.get(__MODULE__, fn val -> val.projects end)
  end

  def add_project() do
  end
end

defmodule Grav1.ProjectsExecutor do
  use GenServer

  alias Grav1.{Projects, Project, Segment}

  defstruct action_queue: :queue.new

  def start_link(_) do
    GenServer.start_link(__MODULE__, %__MODULE__{}, name: __MODULE__)
  end

  def init(state) do
    {:ok, state}
  end

  def do_action(:split, %{input: input, path_split: path_split, min_frames: min_frames, max_frames: max_frames}) do
    Grav1.Split.split(input, path_split, min_frames, max_frames)
  end

  def handle_cast(:loop, state) do
    new_actions = case :queue.out(state.action_queue) do
      {{:value, {action, opts}}, tail} ->
        GenServer.cast(__MODULE__, :loop)

        do_action(action, opts)

        tail
      {:empty, tail} ->
        tail
    end

    {:noreply, %{state | action_queue: new_actions}}
  end

  def handle_cast(:notify, state) do
    GenServer.cast(__MODULE__, :loop)
    {:noreply, state}
  end

  def notify() do
    GenServer.cast(__MODULE__, :notify)
  end
end
