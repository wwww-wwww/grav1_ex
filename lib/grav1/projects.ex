defmodule Grav1.Projects do
  use GenServer

  alias Grav1.{Repo, Project, Projects, WorkerAgent}
  alias Ecto.Multi

  defstruct projects: %{},
            segments: %{}

  def start_link(_) do
    {projects, segments} =
      Repo.all(Project)
      |> Repo.preload(:segments)
      |> Enum.reduce({%{}, %{}}, fn project, {acc, acc2} ->
        segments =
          project.segments
          |> Enum.reduce(%{}, fn segment, segments ->
            if segment.filesize == 0 do
              Map.put(segments, segment.id, %{segment | project: project})
            else
              segments
            end
          end)

        new_project = %{project | segments: segments}
        {Map.put(acc, project.id, new_project), Map.merge(acc2, segments)}
      end)

    GenServer.start_link(__MODULE__, %__MODULE__{projects: projects, segments: segments},
      name: __MODULE__
    )
  end

  def init(state) do
    send(self(), :startup)
    {:ok, state}
  end

  def handle_call({:add_projects, projects}, _, state) do
    {:reply, :ok, %{state | projects: Map.merge(state.projects, projects)}}
  end

  def handle_call(:get_segment, _, state) do
    workers = WorkerAgent.get_workers()

    sorted =
      state.segments
      |> Map.values()
      |> Enum.sort_by(&(&1.frames), :desc)
      |> Enum.sort_by(&(&1.project.priority), :asc)
      |> Enum.sort_by(&(length(Enum.filter(workers, fn worker -> worker.segment == &1.id end))), :asc)

    case sorted do
      [head | _] ->
        {:reply, head, state}
      
      [] ->
        {:reply, nil, state}
    end
  end

  def handle_call(:get_projects, _, state) do
    {:reply, state.projects, state}
  end

  def handle_call({:get_project, id}, _, state) do
    {:reply, Map.get(state.projects, id), state}
  end

  def handle_cast({:log, id, message}, state) do
    case Map.get(state.projects, id) do
      nil ->
        {:noreply, state}

      project ->
        new_project = %{project | log: project.log ++ [{DateTime.utc_now(), message}]}
        Grav1Web.ProjectsLive.update_log(new_project)
        {:noreply, %{state | projects: Map.put(state.projects, project.id, new_project)}}
    end
  end

  def handle_cast({:update_progress, id, status, message}, state) do
    case Map.get(state.projects, id) do
      nil ->
        {:noreply, state}

      project ->
        opts =
          case message do
            {nom, den} ->
              %{status: status, progress_nom: nom, progress_den: den}

            nom ->
              %{status: status, progress_nom: nom, progress_den: 1}
          end

        new_project = Map.merge(project, opts)

        Grav1Web.ProjectsLive.update(new_project, true)
        {:noreply, %{state | projects: Map.put(state.projects, project.id, new_project)}}
    end
  end

  def handle_cast({:update, id, opts, save}, state) do
    case Map.get(state.projects, id) do
      nil ->
        {:noreply, state}

      project ->
        new_project = Map.merge(project, opts)

        if save do
          Repo.update(Project.changeset(project, opts))
        end

        Grav1Web.ProjectsLive.update(new_project)
        {:noreply, %{state | projects: Map.put(state.projects, project.id, new_project)}}
    end
  end

  def handle_info(:startup, state) do
    Enum.each(state.projects, fn {_, project} ->
      load_project(project)
    end)

    {:noreply, state}
  end

  def get_segment() do
    GenServer.call(__MODULE__, :get_segment)
  end

  def get_projects() do
    GenServer.call(__MODULE__, :get_projects)
  end

  def get_project(id) do
    {id, _} = Integer.parse(to_string(id))

    GenServer.call(__MODULE__, {:get_project, id})
  end

  def log(project, message) do
    GenServer.cast(__MODULE__, {:log, project.id, message})
  end

  def update_progress(project, status, message) do
    GenServer.cast(__MODULE__, {:update_progress, project.id, status, message})
  end

  def update_project(project, opts, save \\ false) do
    GenServer.cast(__MODULE__, {:update, project.id, opts, save})
  end

  def add_projects(projects) do
    :ok = GenServer.call(__MODULE__, {:add_projects, projects})

    Enum.each(projects, fn {_, project} ->
      load_project(project)
    end)
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
        completed_frames =
          project.segments
          |> Enum.reduce(0, fn {_, segment}, acc ->
            if segment.filesize != 0 do
              acc + segment.frames
            else
              acc
            end
          end)

        update_project(project, %{
          progress_nom: completed_frames,
          progress_denom: project.input_frames
        })

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

  alias Grav1.{Projects, Project, Segment, Repo}
  alias Ecto.Multi

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    {:ok, state}
  end

  def do_action(:split, project) do
    Grav1.Projects.update_project(project, %{state: :preparing})

    path_split =
      Application.fetch_env!(:grav1, :path_projects)
      |> Path.join(to_string(project.id))
      |> Path.join("split")

    case Grav1.Split.split(
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
         ) do
      {:ok, segments, input_frames} ->
        q =
          segments
          |> Enum.reduce([], fn segment, acc ->
            acc ++
              [
                Segment.changeset(%Segment{}, segment)
                |> Ecto.Changeset.put_assoc(:project, project)
              ]
          end)
          |> Enum.with_index()
          |> Enum.reduce(Multi.new(), fn {segment, i}, acc ->
            acc |> Multi.insert(to_string(i), segment)
          end)

        case Repo.transaction(q) do
          {:ok, transactions} ->
            new_segments =
              transactions
              |> Enum.reduce(%{}, fn {_, x}, acc ->
                Map.put(acc, x.id, x)
              end)

            Projects.update_project(
              project,
              %{
                input_frames: input_frames,
                state: :ready,
                segments: new_segments,
                progress_nom: 0,
                progress_den: input_frames
              },
              true
            )

            :ok

          {:error, failed_operation, failed_value, _successes} ->
            IO.inspect(failed_operation)
            IO.inspect(failed_value)
            {:error, [failed_operation, failed_value]}
        end

      _ ->
        IO.inspect("split failed")
    end
  end

  def add_action(action, opts) do
    GenServer.call(Grav1.ProjectsExecutorQueue, {:push, {action, opts}})
    GenServer.cast(__MODULE__, :loop)
  end

  def handle_cast(:loop, state) do
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
