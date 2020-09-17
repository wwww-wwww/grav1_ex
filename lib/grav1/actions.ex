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

    Grav1.Projects.log(project, Enum.join(args, " "))

    System.cmd(Application.fetch_env!(:grav1, :path_python), args)
  end
end
