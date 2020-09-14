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

  alias Grav1.{Repo, Projects, Segment, VerificationQueue}

  @re_dav1d ~r/Decoded [0-9]+\/([0-9]+) frames/

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    {:ok, state}
  end

  def get_frames("av1", path) do
    args = ["-i", path, "-o", "/dev/null", "--framethreads", "1", "--tilethreads", "16"]

    port =
      Port.open(
        {:spawn_executable, Application.fetch_env!(:grav1, :path_dav1d)},
        [:stderr_to_stdout, :exit_status, :line, args: args]
      )

    Grav1.Split.stream_port(port, 0, fn line, acc ->
      case Regex.scan(@re_dav1d, line) |> List.last() do
        nil ->
          acc

        [_, frame_str] ->
          case Integer.parse(frame_str) do
            :error ->
              acc

            {new_frame, _} ->
              new_frame
          end
      end
    end)
  end

  def get_frames(:aomenc, path) do
    get_frames("av1", path)
  end

  def verify(%{
        segment: segment,
        path: path,
        user: user,
        socket_id: socket_id
      }) do
    frames = segment.frames

    case get_frames(segment.project.encoder, path) do
      {:error, reason} ->
        IO.inspect(reason)

      ^frames ->
        case File.stat(path) do
          {:ok, %{size: size}} ->
            if Projects.finish_segment(segment, size) == :ok do
              new_path =
                Application.fetch_env!(:grav1, :path_projects)
                |> Path.join(to_string(segment.project.id))
                |> Path.join("encode")

              case File.mkdir_p(new_path) do
                :ok ->
                  File.rename(path, Path.join(new_path, "#{segment.n}.ivf"))

                {:error, reason} ->
                  IO.inspect(reason)
                  File.rm(path)
              end
            end

          {:error, reason} ->
            IO.inspect(reason)
            File.rm(path)
        end

      bad_frames ->
        IO.inspect("bad framecount #{bad_frames}, expected #{frames}")
        File.rm(path)
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
      verify(job)
      GenServer.call(VerificationQueue, {:remove, job})
      GenServer.cast(__MODULE__, :loop)
    end

    {:noreply, state}
  end
end
