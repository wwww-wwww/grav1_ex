defmodule Grav1.Projects do
  use Agent

  alias Grav1Web.Endpoint
  alias Grav1.{Repo, Project, Segment}
  alias Ecto.Multi

  defstruct projects: %{}

  def start_link(_) do
    Agent.start_link(
      fn ->
        projects =
          Repo.all(Project)
          |> Repo.preload(:segments)
          |> Enum.reduce(%{}, fn x, acc ->
            Map.put(acc, x.id, x)
          end)

        Enum.each(projects, fn {_, project} ->
          load_project(project)
        end)

        %__MODULE__{projects: projects}
      end,
      name: __MODULE__
    )
  end

  def get_projects() do
    Agent.get(__MODULE__, fn val -> val.projects end)
  end

  def log(project, message) do
    Agent.get_and_update(__MODULE__, fn val ->
      case Map.get(val.projects, project.id) do
        nil ->
          {project, val}

        project_l ->
          new_project = %{project_l | log: project_l.log ++ [message]}
          {new_project, %{val | projects: Map.put(val.projects, project.id, new_project)}}
      end
    end)
    |> Grav1Web.ProjectsLive.update_only()
  end

  def update_progress(project, status, message) do
    new_project =
      Agent.get_and_update(__MODULE__, fn val ->
        case Map.get(val.projects, project.id) do
          nil ->
            {project, val}

          project_l ->
            opts =
              case message do
                {nom, den} ->
                  %{status: status, progress_nom: nom, progress_den: den}

                nom ->
                  %{status: status, progress_nom: nom, progress_den: 1}
              end

            new_project = Map.merge(project_l, opts)
            {new_project, %{val | projects: Map.put(val.projects, project.id, new_project)}}
        end
      end)

    Grav1Web.ProjectsLive.update(new_project, true)
  end

  def update_project(project, opts, save \\ false) do
    new_project =
      Agent.get_and_update(__MODULE__, fn val ->
        case Map.get(val.projects, project.id) do
          nil ->
            {project, val}

          project_l ->
            new_project = Map.merge(project_l, opts)
            {new_project, %{val | projects: Map.put(val.projects, project.id, new_project)}}
        end
      end)

    if save do
      Repo.update(Ecto.Changeset.change(project, opts))
    end

    Grav1Web.ProjectsLive.update(new_project)
  end

  defp ensure_not_empty(input) do
    case input do
      {:error, message} -> {:error, message}
      [] -> {:error, ["Files can't be empty."]}
      _ -> input
    end
  end

  defp ensure_exist(input) do
    case input do
      {:error, message} ->
        {:error, message}

      files ->
        case Enum.filter(files, fn file -> not File.exists?(file) end) do
          [] ->
            files

          missing_files ->
            message = "Files can't be found: " <> Enum.join(missing_files, ", ")
            {:error, [message]}
        end
    end
  end

  def add_projects(projects) do
    Agent.update(__MODULE__, fn val ->
      %{val | projects: Map.merge(val.projects, projects)}
    end)

    Enum.each(projects, fn {_, project} ->
      load_project(project)
    end)
  end

  def add_project(files, opts) do
    case files
         |> ensure_not_empty
         |> ensure_exist do
      {:error, message} ->
        {:error, message}

      _ ->
        projects =
          Enum.reduce(files, [], fn filename, acc ->
            acc ++
              [
                Project.changeset(%Project{input: filename}, opts)
              ]
          end)

        case projects |> Enum.at(0) do
          %{valid?: false, errors: errors} ->
            new_errors =
              Enum.reduce([], fn {x, {error, _}}, acc ->
                acc ++ ["#{x} #{error}"]
              end)

            {:error, new_errors}

          _ ->
            q =
              projects
              |> Enum.with_index()
              |> Enum.reduce(Multi.new(), fn {project, i}, acc ->
                acc |> Multi.insert(to_string(i), project)
              end)

            case Repo.transaction(q) do
              {:ok, transactions} ->
                transactions
                |> Enum.reduce(%{}, fn {_, x}, acc ->
                  Map.put(acc, x.id, x)
                end)
                |> add_projects()

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

  def load_project(project) do
    case project do
      %{state: :idle} ->
        Grav1.ProjectsExecutor.add_action(:split, project)

      %{state: :ready} ->
        IO.inspect(project)

      _ ->
        IO.inspect(project)
    end
  end
end

defmodule Grav1.ProjectsExecutorQueue do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, :queue.new(), name: __MODULE__)
  end

  def init(state) do
    {:ok, state}
  end

  def handle_call({:push, action}, _, state) do
    {:reply, :ok, :queue.in(action, state)}
  end

  def handle_call(:pop, _, state) do
    case :queue.out(state) do
      {{:value, action}, tail} ->
        {:reply, action, tail}

      {:empty, tail} ->
        {:reply, :empty, tail}
    end
  end
end

defmodule Grav1.ProjectsExecutor do
  use GenServer

  alias Grav1.{Projects, Project, Segment}

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    {:ok, state}
  end

  def do_action(:split, project) do
    Grav1.Projects.update_project(project, %{state: :preparing})

    path_split = "#{project.id}"

    Grav1.Split.split(
      project.input,
      path_split,
      project.split_min_frames,
      project.split_max_frames,
      fn type, message ->
        case type do
          :log ->
            Projects.log(project, message)

          {:progress, action} ->
            Projects.update_progress(project, action, message)
        end
      end
    )
  end

  def add_action(action, opts) do
    GenServer.call(Grav1.ProjectsExecutorQueue, {:push, {action, opts}})
    GenServer.cast(__MODULE__, :loop)
  end

  def handle_cast(:loop, state) do
    IO.inspect("loop")

    case GenServer.call(Grav1.ProjectsExecutorQueue, :pop) do
      :empty ->
        IO.inspect("finished queue")

      {action, opts} ->
        GenServer.cast(__MODULE__, :loop)

        do_action(action, opts)
    end

    {:noreply, state}
  end
end
