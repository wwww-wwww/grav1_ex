defmodule Grav1Web.ApiController do
  use Grav1Web, :controller

  alias Grav1.{Projects, Repo, User, VerificationExecutor}

  def get_segment(conn, %{"id" => id}) do
    case Projects.get_segment(id) do
      nil ->
        conn
        |> json(%{reason: "segment not found"})

      segment ->
        path =
          Application.fetch_env!(:grav1, :path_projects)
          |> Path.join(to_string(segment.project.id))
          |> Path.join("split")
          |> Path.join(segment.file)

        conn
        |> send_download({:file, path})
    end
  end

  def add_project(
        conn,
        %{
          "files" => files,
          "encoder" => encoder,
          "encoder_params" => encoder_params,
          "extra_params" => %{
            "split" => %{"min_frames" => min_frames, "max_frames" => max_frames},
            "name" => name,
            "priority" => priority,
            "on_complete" => on_complete,
            "on_complete_params" => on_complete_params,
            "ffmpeg_params" => ffmpeg_params
          },
          "key" => key
        }
      ) do
    case Repo.get_by(User, key: key) do
      nil ->
        conn |> json(%{success: false, reason: "bad key"})

      user ->
        case Projects.add_project(files, %{
               encoder: encoder,
               encoder_params: encoder_params,
               ffmpeg_params: ffmpeg_params,
               split_min_frames: min_frames,
               split_max_frames: max_frames,
               name: name,
               priority: priority,
               on_complete: on_complete,
               on_complete_params: on_complete_params
             }) do
          :ok ->
            conn |> json(%{success: true})

          {:error, reason} ->
            conn |> json(%{success: false, reason: reason})

          err ->
            conn |> json(%{success: false, reason: inspect(err)})
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
             "passes" => passes
           }} ->
            case Projects.get_segment(segment_id) do
              nil ->
                conn |> json(%{success: false, reason: "segment not found"})

              segment ->
                if encoder_params == segment.project.encoder_params and
                     ffmpeg_params == segment.project.ffmpeg_params and
                     passes == 2 do
                  new_path =
                    Application.fetch_env!(:grav1, :path_verification)
                    |> Path.join("#{segment_id}_#{socket_id}_#{Ecto.UUID.generate()}.ivf")
                    |> Path.absname()

                  File.cp(path, new_path)
                  VerificationExecutor.add_segment(segment, new_path, user, socket_id)
                  conn |> json(%{success: true})
                else
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
end
