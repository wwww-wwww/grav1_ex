defmodule Grav1.VerificationQueue do
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

defmodule Grav1.VerificationExecutor do
  use GenServer

  alias Grav1.{Repo, User, Projects, VerificationQueue}

  import Ecto.Query, only: [from: 2]

  @re_dav1d ~r/Decoded [0-9]+\/([0-9]+) frames/
  @re_ffmpeg_frames_d ~r/([0-9]+?) frames successfully decoded/

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    {:ok, state}
  end

  def get_frames("av1", path) do
    args = ["-i", path, "--muxer", "null", "--framethreads", "1", "--tilethreads", "16"]

    case System.cmd(Grav1.get_path(:dav1d), args, stderr_to_stdout: true) do
      {resp, 0} ->
        case Regex.scan(@re_dav1d, resp) |> List.last() do
          [_, frame_str] ->
            {frame, _} = Integer.parse(frame_str)
            frame

          _ ->
            {:error, resp}
        end

      resp ->
        {:error, resp}
    end
  end

  def get_frames(:aomenc, path) do
    get_frames("av1", path)
  end

  def get_frames(_, path) do
    args = ["-hide_banner", "-loglevel", "debug", "-i", path, "-f", "null", "-"]

    case System.cmd(Grav1.get_path(:ffmpeg), args, stderr_to_stdout: true) do
      {resp, 0} ->
        case Regex.scan(@re_ffmpeg_frames_d, resp) |> List.last() do
          [_, frame_str] ->
            {frame, _} = Integer.parse(frame_str)
            frame

          _ ->
            {:error, resp}
        end

      resp ->
        {:error, resp}
    end
  end

  def verify(%{
        segment: segment,
        path: path,
        user: user,
        socket_id: socket_id
      }) do
    frames = segment.frames
    username = user.username

    case get_frames(segment.project.encoder, path) do
      {:error, err} ->
        err

      ^frames ->
        case File.stat(path) do
          {:ok, %{size: size}} ->
            case Projects.finish_segment(segment, size) do
              {:ok, project} ->
                new_path =
                  Application.fetch_env!(:grav1, :path_projects)
                  |> Path.join(to_string(segment.project.id))
                  |> Path.join("encode")

                case File.mkdir_p(new_path) do
                  :ok ->
                    File.rename(path, Path.join(new_path, "#{segment.n}.ivf"))

                    from(u in User,
                      update: [inc: [frames: ^frames]],
                      where: u.username == ^username
                    )
                    |> Repo.update_all([])

                    Grav1Web.ProjectsLive.update(project)
                    Grav1.WorkerAgent.cancel_segments()

                    incomplete_segments =
                      :maps.filter(fn _, v -> v.filesize == 0 end, project.segments)

                    if map_size(incomplete_segments) == 0 do
                      Grav1.ProjectsExecutor.add_action(:concat, project)
                    end

                    {:ok, project, segment}

                  err ->
                    File.rm(path)
                    err
                end

              err ->
                File.rm(path)
                err
            end

          err ->
            File.rm(path)
            err
        end

      {:error, 1, bad_frames} ->
        File.rm(path)
        {:error, "bad framecount #{bad_frames}, expected #{frames}"}

      bad_frames when is_integer(bad_frames) ->
        File.rm(path)
        {:error, "bad framecount #{bad_frames}, expected #{frames}"}

      err ->
        File.rm(path)
        err
    end
  end

  def add_segment(segment, path, user, socket_id) do
    GenServer.call(
      VerificationQueue,
      {:push,
       %{
         segment: segment,
         path: path,
         user: user,
         socket_id: socket_id
       }}
    )

    GenServer.cast(__MODULE__, :loop)
  end

  def get_queue() do
    GenServer.call(VerificationQueue, :get)
  end

  def handle_cast(:loop, state) do
    if (job = GenServer.call(VerificationQueue, :pop)) != :empty do
      resp = verify(job)
      GenServer.call(VerificationQueue, {:remove, job})

      case resp do
        {:ok, project, segment} ->
          Grav1Web.ProjectsLive.update_segments(project, [{segment, []}])

        {:error, err} ->
          Projects.log(job.segment.project, inspect(err))

        err ->
          Projects.log(job.segment.project, inspect(err))
      end

      GenServer.cast(__MODULE__, :loop)
    end

    {:noreply, state}
  end
end
