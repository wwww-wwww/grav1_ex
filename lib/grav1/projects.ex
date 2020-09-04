defmodule Grav1.Projects do
  use Agent

  alias Grav1Web.Endpoint
  alias Grav1.{Repo, Project, Segment}
  alias Ecto.Multi

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

  def ensure_not_empty(input) do
    case input do
      {:error, message} -> {:error, message}
      [] -> {:error, ["Files can't be empty."]}
      _ -> input
    end
  end

  def ensure_exist(input) do
    case input do
      {:error, message} -> {:error, message}
      files ->
        case Enum.filter(files, fn file -> not File.exists?(file) end) do
          [] -> files
          missing_files ->
            message = "Files can't be found: " <> Enum.join(missing_files, ", ")
            {:error, [message]}
        end
    end
  end

  def add_project(files, encoder, encoder_params) do
    case files
    |> ensure_not_empty
    |> ensure_exist do
      {:error, message} -> {:error, message}
      _ ->
        projects = Enum.reduce(files, [], fn filename, acc ->
          acc ++ [Project.changeset(%Project{input: filename}, %{encoder: encoder, encoder_params: encoder_params, ffmpeg_params: []})]
        end)
        case projects |> Enum.at(0) do
          %{valid?: false, errors: errors} ->
            new_errors = Enum.reduce([], fn {x, {error, _}}, acc ->
              acc ++ ["#{x} #{error}"]
            end)

            {:error, new_errors}
          _ ->
            q = projects
            |> Enum.with_index()
            |> Enum.reduce(Multi.new(), fn {project, i}, acc ->
              acc |> Multi.insert(to_string(i), project)
            end)

            case Repo.transaction(q) do
              {:ok, transactions} ->
                Agent.update(__MODULE__, fn val ->
                  new_projects = val.projects ++ Map.values(transactions)
                  %{val | projects: new_projects}
                end)
                Grav1Web.ProjectsLive.update()
                :ok
              {:error, failed_operation, failed_value, _successes} ->
                IO.inspect(failed_operation)
                IO.inspect(failed_value)
                {:error, [failed_operation, failed_value]}
            end
        end
    end
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
