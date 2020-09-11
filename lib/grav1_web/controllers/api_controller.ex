defmodule Grav1Web.ApiController do
  use Grav1Web, :controller

  alias Grav1.{Projects}

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
        |> send_download({:file, Application.app_dir(:grav1, path)})
    end
  end
end
