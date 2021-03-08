defmodule Grav1.Projects do
  use GenServer

  alias Grav1.{Repo, Project, Projects, WorkerAgent, ProjectsExecutor}
  alias Ecto.Multi

  import Ecto.Query, only: [from: 2]

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
            Map.put(segments, segment.id, %{segment | project: %{project | segments: %{}}})
          end)

        new_segments =
          if project.state == :ready do
            :maps.filter(fn _, v -> v.filesize == 0 end, segments)
            |> Map.merge(acc2)
          else
            acc2
          end

        new_project = %{project | segments: segments}
        {Map.put(acc, project.id, new_project), new_segments}
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

  def handle_call({:get_segments, clients, filter}, _, state) do
    {workers, limit} =
      clients
      |> Enum.reduce({[], 0}, fn {_, client}, {acc_w, acc_l} ->
        {acc_w ++ client.state.workers,
         acc_l + length(client.state.workers) + client.state.max_workers + client.state.queue_size}
      end)

    sorted =
      state.segments
      |> Map.values()
      |> Enum.sort_by(& &1.frames, :desc)
      |> Enum.sort_by(& &1.project.priority, :asc)
      |> Enum.take(limit)
      |> Enum.sort_by(
        &map_size(
          :maps.filter(
            fn _, client ->
              &1.id == client.sending.downloading or
                &1.id == client.state.downloading or
                &1.id in client.state.job_queue or
                &1.id in client.state.upload_queue or
                &1.id in client.state.uploading
            end,
            clients
          )
        ),
        :asc
      )
      |> Enum.sort_by(
        &length(Enum.filter(workers, fn worker -> worker.segment == &1.id end)),
        :asc
      )
      |> Enum.sort_by(
        &(&1.id in filter),
        :asc
      )

    {:reply, sorted, state}
  end

  def handle_call(:get_segments, _, state) do
    {:reply, state.segments, state}
  end

  def handle_call(:get_segments_keys, _, state) do
    {:reply, Map.keys(state.segments), state}
  end

  def handle_call(:get_projects, _, state) do
    {:reply, state.projects, state}
  end

  def handle_call({:get_project, id}, _, state) do
    {:reply, Map.get(state.projects, id), state}
  end

  def handle_call({:finish_segment, segment, filesize}, _, state) do
    case Map.get(state.projects, segment.project_id) do
      nil ->
        {:reply, {:error, "cant find project"}, state}

      project ->
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

  def handle_call({:add_segments, segments}, _, state) do
    {:reply, :ok, %{state | segments: Map.merge(state.segments, segments)}}
  end

  def handle_call({:reload_project, id}, _, state) do
    project =
      Repo.get(Project, id)
      |> Repo.preload(:segments)

    segments =
      project.segments
      |> Enum.reduce(%{}, fn segment, segments ->
        Map.put(segments, segment.id, %{segment | project: %{project | segments: %{}}})
      end)

    new_segments = :maps.filter(fn _, v -> v.project_id != id end, state.segments)

    new_segments =
      if project.state == :ready do
        :maps.filter(fn _, v -> v.filesize == 0 end, segments)
        |> Map.merge(new_segments)
      else
        new_segments
      end

    new_project = %{project | segments: segments}
    new_projects = Map.put(state.projects, project.id, new_project)
    new_state = %{state | projects: new_projects, segments: new_segments}

    {:reply, new_project, new_state}
  end

  def handle_call(:sync, _, state) do
    q =
      from p in Project,
        select: p.id

    projects = Repo.all(q)

    new_projects = :maps.filter(fn _, v -> v.id in projects end, state.projects)
    new_segments = :maps.filter(fn _, v -> v.project_id in projects end, state.segments)

    {:reply, new_projects, %{state | projects: new_projects, segments: new_segments}}
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

  def handle_cast({:update, ids, opts, save}, state) do
    {new_projects, new_state} =
      Enum.reduce(ids, {[], state}, fn id, {projects, acc} ->
        case Map.get(state.projects, id) do
          nil ->
            {projects, acc}

          project ->
            new_project = Map.merge(project, opts)

            if save do
              Repo.update(Project.changeset(project, opts))
            end

            new_segments =
              acc.segments
              |> Enum.map(fn {sid, segment} ->
                if segment.project_id == id do
                  {sid, %{segment | project: new_project}}
                else
                  {sid, segment}
                end
              end)
              |> Map.new()

            {projects ++ [new_project],
             %{
               acc
               | projects: Map.put(acc.projects, project.id, new_project),
                 segments: new_segments
             }}
        end
      end)

    Grav1Web.ProjectsLive.update_projects(new_projects)

    {:noreply, new_state}
  end

  def handle_info(:startup, state) do
    Enum.each(state.projects, fn {_, project} ->
      load_project(project)
    end)

    WorkerAgent.distribute_segments()

    {:noreply, state}
  end

  def get_segment(id) do
    {id, _} = Integer.parse(to_string(id))

    GenServer.call(__MODULE__, {:get_segment, id})
  end

  def get_segments(clients, filter) do
    GenServer.call(__MODULE__, {:get_segments, clients, filter})
  end

  def get_segments() do
    GenServer.call(__MODULE__, :get_segments)
  end

  def get_segments_keys() do
    GenServer.call(__MODULE__, :get_segments_keys)
  end

  def get_projects() do
    GenServer.call(__MODULE__, :get_projects)
  end

  def get_project(id) do
    {id, _} = Integer.parse(to_string(id))

    GenServer.call(__MODULE__, {:get_project, id})
  end

  def reload_projects(ids) do
    Enum.map(ids, fn id ->
      GenServer.call(__MODULE__, {:reload_project, id})
      |> load_project(false)
    end)
    |> Grav1Web.ProjectsLive.update_projects(true)
  end

  def reload_project(id) do
    reload_projects([id]) |> Enum.at(0)
  end

  def start_projects(projects) do
    Enum.map(projects, & &1.id)
    |> update_projects(%{state: :ready}, true)
    |> reload_projects()
  end

  def start_project(project) do
    start_projects([project]) |> Enum.at(0)
  end

  def stop_projects(projects) do
    Enum.map(projects, & &1.id)
    |> update_projects(%{state: :idle}, true)
    |> reload_projects()
  end

  def stop_project(project) do
    stop_projects([project]) |> Enum.at(0)
  end

  def remove_projects(ids) do
    ids
    |> Enum.filter(fn id ->
      case Repo.get(Project, id) do
        nil ->
          false

        project ->
          Repo.delete(project)
      end
    end)
    |> case do
      [_ | _] ->
        sync()

      _ ->
        :nothing
    end
  end

  def sync() do
    GenServer.call(__MODULE__, :sync)
    |> Map.values()
    |> Grav1Web.ProjectsLive.update_projects(true)
  end

  def log(project, message) do
    GenServer.cast(__MODULE__, {:log, project.id, message})
  end

  def update_progress(project, status, message) do
    GenServer.cast(__MODULE__, {:update_progress, project.id, status, message})
  end

  def update_projects(projects, opts, save \\ false) do
    GenServer.cast(__MODULE__, {:update, projects, opts, save})
    projects
  end

  def update_project(project, opts, save \\ false) do
    update_projects([project.id], opts, save)

    log(project, "updated: " <> inspect(opts))
  end

  def finish_segment(segment, filesize) do
    GenServer.call(__MODULE__, {:finish_segment, segment, filesize})
  end

  def add_segments(segments) do
    GenServer.call(__MODULE__, {:add_segments, segments})
  end

  defp ensure_supported_encoder(input) do
    case input do
      {:error, message} ->
        {:error, message}

      opts ->
        if String.to_atom(opts["encoder"]) in Application.fetch_env!(:grav1, :encoders) do
          opts
        else
          {:error,
           "Encoder not supported. Supported encoders: " <>
             inspect(Application.fetch_env!(:grav1, :encoders))}
        end
    end
  end

  defp ensure_supported_action(input) do
    case input do
      {:error, message} ->
        {:error, message}

      opts ->
        if String.length(opts["on_complete"]) == 0 or
             opts["on_complete"] in Grav1.Actions.get() do
          opts
        else
          {:error,
           "Action not supported. Supported actions: " <>
             inspect(Grav1.Actions.get())}
        end
    end
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

  defp add_project_p(files, opts) do
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
        projects
        |> Enum.with_index()
        |> Enum.reduce(Multi.new(), fn {project, i}, acc ->
          acc |> Multi.insert(to_string(i), project)
        end)
        |> Repo.transaction()
        |> case do
          {:ok, transactions} ->
            transactions
            |> Enum.reduce(%{}, fn {_, project}, acc ->
              Map.put(acc, project.id, %{
                project
                | segments: %{}
              })
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

  def add_project(files, opts) do
    files
    |> ensure_not_empty
    |> ensure_exist
    |> case do
      {:error, message} ->
        {:error, message}

      _ ->
        case opts
             |> ensure_supported_encoder
             |> ensure_supported_action do
          {:error, message} ->
            {:error, message}

          _ ->
            add_project_p(files, opts)
        end
    end
  end

  def load_project(project, update \\ true) do
    if project.state == :idle and
         (project.segments == %Ecto.Association.NotLoaded{} or
            map_size(project.segments) == 0) do
      ProjectsExecutor.add_action(:split, project)
    else
      if project.state in [:ready, :idle] do
        completed_segments = :maps.filter(fn _, v -> v.filesize != 0 end, project.segments)

        completed_frames =
          completed_segments
          |> Enum.reduce(0, &(&2 + elem(&1, 1).frames))

        update_project(project, %{
          progress_num: completed_frames,
          progress_den: project.input_frames
        })

        if map_size(completed_segments) == map_size(project.segments) do
          ProjectsExecutor.add_action(:concat, project)
        end

        if update do
          Grav1Web.ProjectsLive.update(project)
        end
      end

      log(project, "loaded")
    end

    project
  end

  def reset_projects(projects, params) do
    Enum.reduce(projects, Ecto.Multi.new(), fn project, acc ->
      id = project.id

      changeset = Project.changeset(project, %{state: :idle, encoder_params: params})

      segments_query =
        from s in Grav1.Segment, where: s.project_id == ^id, update: [set: [filesize: 0]]

      acc
      |> Ecto.Multi.update("project:#{project.id}", changeset)
      |> Ecto.Multi.update_all("segments:#{project.id}", segments_query, [])
    end)
    |> Repo.transaction()
    |> case do
      {:ok, _} ->
        reload_projects(Enum.map(projects, & &1.id))
        WorkerAgent.distribute_segments()

        :ok

      err ->
        err
    end
  end

  def reset_project(project, params) do
    reset_projects([project], params)
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

  def do_action(:concat, project) do
    Grav1.Concat.concat(project)
  end

  def do_action(:split, project) do
    Projects.update_project(project, %{state: :preparing})

    path_split =
      Application.fetch_env!(:grav1, :path_projects)
      |> Path.join(to_string(project.id))
      |> Path.join("split")

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
    |> case do
      {:ok, segments, input_frames} ->
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
        |> Repo.transaction()
        |> case do
          {:ok, transactions} ->
            new_segments =
              transactions
              |> Enum.reduce(%{}, fn {_, x}, acc ->
                Map.put(acc, x.id, x)
              end)

            new_state = if project.start_after_split, do: :ready, else: :idle

            Projects.update_project(
              project,
              %{
                input_frames: input_frames,
                state: new_state,
                segments: new_segments,
                progress_num: 0,
                progress_den: input_frames
              },
              true
            )

            if project.start_after_split do
              Projects.add_segments(new_segments)
              Grav1.WorkerAgent.distribute_segments()
            end

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
