defmodule Grav1Web.ApiController do
  use Grav1Web, :controller

  alias Grav1.{Projects, Repo, User, VerificationExecutor, WorkerAgent}

  def get_segment(conn, %{"id" => id}) do
    case Projects.get_segment(id) do
      nil ->
        conn
        |> json(%{reason: "segment not found"})

      segment ->
        path =
          "/segment"
          |> Path.join(to_string(segment.project_id))
          |> Path.join("split")
          |> Path.join(segment.file)

        conn
        |> redirect(to: Routes.static_path(conn, path))
    end
  end

  def add_project(conn, %{"files" => files, "params" => params, "key" => key}) do
    case Repo.get_by(User, key: key) do
      nil ->
        conn |> json(%{success: false, reason: "bad key"})

      user ->
        if user.level >= 100 do
          case Projects.add_project(files, params) do
            :ok ->
              conn |> json(%{success: true})

            {:error, reason} ->
              conn |> json(%{success: false, reason: reason})

            err ->
              conn |> json(%{success: false, reason: inspect(err)})
          end
        else
          conn |> json(%{success: false, reason: "You are not allowed to do this!"})
        end
    end
  end

  def set_workers(conn, %{"name" => name, "max_workers" => max_workers, "key" => key}) do
    {max_workers, _} = Integer.parse(to_string(max_workers))

    case Repo.get_by(User, key: key) do
      nil ->
        conn |> json(%{success: false, reason: "bad key"})

      user ->
        case WorkerAgent.get_clients_by_name(user.username, name) do
          [] ->
            conn |> json(%{success: false, reason: "No clients by this name found"})

          clients ->
            clients
            |> Enum.map(&elem(&1, 0))
            |> WorkerAgent.update_clients(sending: %{max_workers: max_workers})

            conn |> json(%{success: true})
        end
    end
  end

  def finish_segment(conn, %{
        "key" => key,
        "socket_id" => socket_id,
        "segment" => segment_id,
        "file" => %Plug.Upload{
          path: path
        },
        "encode_settings" => encode_settings
      }) do
    case Repo.get_by(User, key: key) do
      nil ->
        conn
        |> json(%{success: false, reason: "bad key"})

      user ->
        case Jason.decode(encode_settings) do
          {:ok,
           %{
             "encoder_params" => encoder_params,
             "ffmpeg_params" => ffmpeg_params,
             "passes" => passes,
             "encoder" => encoder,
             "version" => version
           }} ->
            case Projects.get_segment(segment_id) do
              nil ->
                conn |> json(%{success: false, reason: "segment not found"})

              segment ->
                cond do
                  version != Application.fetch_env!(:versions, String.to_atom(encoder)) ->
                    conn |> json(%{success: false, reason: "bad version of" <> encoder})

                  encoder_params == segment.project.encoder_params and
                    ffmpeg_params == segment.project.ffmpeg_params and
                    String.to_atom(encoder) == segment.project.encoder and
                      passes == 2 ->
                    new_path =
                      Application.fetch_env!(:grav1, :path_verification)
                      |> Path.join("#{segment_id}_#{socket_id}_#{Ecto.UUID.generate()}.ivf")
                      |> Path.absname()

                    File.cp(path, new_path)
                    VerificationExecutor.add_segment(segment, new_path, user, socket_id)
                    conn |> json(%{success: true})

                  true ->
                    conn |> json(%{success: false, reason: "outdated segment settings"})
                end
            end

          {:error, reason} ->
            conn |> json(%{success: false, reason: inspect(reason)})
        end
    end
  end

  def finish_segment(conn, opts) do
    IO.inspect(opts)
    conn |> json(%{success: false, reason: "bad request"})
  end

  def versions(conn, _) do
    conn
    |> json(Application.get_all_env(:versions) |> Map.new())
  end
end
