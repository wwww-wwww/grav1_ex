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
            Map.put(segments, segment.id, %{segment | project: project})
          end)

        incomplete_segments = for {k, v} <- segments, v.filesize == 0, into: %{}, do: {k, v}

        new_project = %{project | segments: segments}
        {Map.put(acc, project.id, new_project), Map.merge(acc2, incomplete_segments)}
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

  def handle_call({:get_segment, id}, _, state) do
    {:reply, Map.get(state.segments, id), state}
  end

  def handle_call({:get_segments, clients, n, filter}, _, state) do
    workers =
      clients
      |> Enum.reduce([], fn {_, client}, acc ->
        acc ++ client.workers
      end)

    sorted =
      state.segments
      |> Map.values()
      |> Enum.filter(fn segment ->
        segment.id not in filter
      end)
      |> Enum.sort_by(& &1.frames, :desc)
      |> Enum.sort_by(& &1.project.priority, :asc)
      |> Enum.sort_by(
        &length(
          Enum.filter(clients, fn {_, client} ->
            client.downloading == &1.id or &1.id in client.job_queue
          end)
        ),
        :asc
      )
      |> Enum.sort_by(
        &length(Enum.filter(workers, fn worker -> worker.segment == &1.id end)),
        :asc
      )

    {:reply, Enum.take(sorted, n), state}
  end

  def handle_call(:get_projects, _, state) do
    {:reply, state.projects, state}
  end

  def handle_call({:get_project, id}, _, state) do
    {:reply, Map.get(state.projects, id), state}
  end

  def handle_call({:finish_segment, segment, filesize}, _, state) do
    case Map.get(state.projects, segment.project.id) do
      nil ->
        {:reply, {:error, "cant find project"}, state}

      project ->
        case Map.get(state.segments, segment.id) do
          nil ->
            {:reply, {:error, "can't find segment"}, state}

          segment ->
            case Repo.update(Ecto.Changeset.change(segment, filesize: filesize)) do
              {:ok, new_segment} ->
                {new_project, new_projects} =
                  Map.get_and_update(state.projects, project.id, fn state_project ->
                    new_project_segments =
                      state_project.segments
                      |> Map.update!(segment.id, fn _ ->
                        %{new_segment | filesize: filesize}
                      end)

                    completed_frames =
                      new_project_segments
                      |> Enum.reduce(0, fn {_, segment}, acc ->
                        if segment.filesize != 0 do
                          acc + segment.frames
                        else
                          acc
                        end
                      end)

                    new_project = %{
                      state_project
                      | segments: new_project_segments,
                        progress_num: completed_frames
                    }

                    {new_project, new_project}
                  end)

                new_segments = Map.delete(state.segments, segment.id)

                {:reply, {:ok, new_project},
                 %{state | projects: new_projects, segments: new_segments}}

              {:error, cs} ->
                {:reply, {:error, cs}, state}
            end
        end
    end
  end

  def handle_call({:add_segments, segments}, _, state) do
    {:reply, :ok, %{state | segments: Map.merge(state.segments, segments)}}
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
              %{status: status, progress_num: nom, progress_den: den}

            nom ->
              %{status: status, progress_num: nom, progress_den: 1}
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

    WorkerAgent.distribute_segments_cast()

    {:noreply, state}
  end

  def get_segment(id) do
    {id, _} = Integer.parse(to_string(id))

    GenServer.call(__MODULE__, {:get_segment, id})
  end

  def get_segments(workers, n, filter) do
    GenServer.call(__MODULE__, {:get_segments, workers, n, filter})
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

  def finish_segment(segment, filesize) do
    GenServer.call(__MODULE__, {:finish_segment, segment, filesize})
  end

  def add_segments(segments) do
    GenServer.call(__MODULE__, {:add_segments, segments})
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
    :ok = GenServer.call(__MODULE__, {:add_projects, projects})

    Enum.each(projects, fn {_, project} ->
      load_project(project)
    end)

    WorkerAgent.distribute_segments()
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
              errors
              |> Enum.reduce([], fn {x, {error, _}}, acc ->
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
          progress_num: completed_frames,
          progress_den: project.input_frames
        })

        Projects.log(project, "loaded")

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

  alias Grav1.{Projects, Segment, Repo}
  alias Ecto.Multi

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    case File.mkdir_p(Application.fetch_env!(:grav1, :path_projects)) do
      :ok ->
        {:ok, state}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  def do_action(:split, project) do
    Projects.update_project(project, %{state: :preparing})

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
                progress_num: 0,
                progress_den: input_frames
              },
              true
            )

            Projects.add_segments(new_segments)

            Grav1.WorkerAgent.distribute_segments()

            :ok

          {:error, failed_operation, failed_value, _successes} ->
            IO.inspect(failed_operation)
            IO.inspect(failed_value)
            {:error, [failed_operation, failed_value]}
        end

      {:error, message} ->
        Projects.log(project, message)
    end
  end

  def add_action(action, opts) do
    GenServer.call(Grav1.ProjectsExecutorQueue, {:push, {action, opts}})
    GenServer.cast(__MODULE__, :loop)
  end

  def handle_cast(:loop, state) do
    if (item = GenServer.call(Grav1.ProjectsExecutorQueue, :pop)) != :empty do
      {action, opts} = item

      GenServer.cast(__MODULE__, :loop)

      do_action(action, opts)
    end

    {:noreply, state}
  end
end
