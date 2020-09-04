defmodule Grav1Web.ProjectController do
  use Grav1Web, :controller

  def add_project(conn, params) do
    %{
      "input" => input,
      "encoder" => encoder,
      "encoder_params" => encoder_params,
      "ffmpeg_params" => ffmpeg_params,
      "min_frames" => min_frames,
      "max_frames" => max_frames,
      "on_complete" => on_complete,
      "priority" => priority,
      "id" => id
    } = params

    IO.inspect(params)
    text(conn, "")
  end
end
