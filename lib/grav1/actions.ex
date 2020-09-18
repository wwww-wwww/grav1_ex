defmodule Grav1.Actions do
  def run_complete(project, output) do
    args =
      [
        "-u",
        project.on_complete,
        to_string(project.id),
        project.input,
        output
      ]
      |> Enum.concat(project.on_complete_params)

    Grav1.Projects.log(project, "Running #{project.on_complete} " <> Enum.join(args, " "))

    case System.cmd(Application.fetch_env!(:grav1, :path_python), args, stderr_to_stdout: true) do
      {_, 0} ->
        Grav1.Projects.log(project, project.on_complete <> " exited with code 0")
      {resp, 1} ->
        Grav1.Projects.log(project, project.on_complete <> " exited with code 1")
        Grav1.Projects.log(project, resp)
    end
  end
end
