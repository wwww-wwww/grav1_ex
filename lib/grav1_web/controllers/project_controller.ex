defmodule Grav1Web.ProjectController do
  use Grav1Web, :controller

  def add_project(conn, params) do
    %{
      "files" => files,
      "encoder" => encoder,
      "encoder_params" => encoder_params,
      "ffmpeg_params" => ffmpeg_params,
      "min_frames" => min_frames,
      "max_frames" => max_frames,
      # "on_complete" => on_complete,
      "priority" => priority,
      "name" => name
    } = params

    case Grav1.Projects.add_project(files, %{
           encoder: encoder,
           encoder_params: encoder_params,
           split_min_frames: min_frames,
           split_max_frames: max_frames,
           name: name,
           priority: priority,
           ffmpeg_params: ffmpeg_params
         }) do
      {:error, reason} ->
        json(conn, %{success: false, reason: reason})

      _ ->
        json(conn, %{success: true})
    end
  end
end
