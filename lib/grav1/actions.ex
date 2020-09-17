defmodule Grav1.Actions do
  def run_complete(project, output) do
    args =
      [
        "-u",
        project.on_complete,
        project.id,
        project.input,
        output
      ]
      |> Enum.concat(project.on_complete_params)

    Projects.log(project, Enum.join(args, " "))

    port =
      Port.open(
        {:spawn_executable, Application.fetch_env!(:grav1, :path_python)},
        [:stderr_to_stdout, :binary, :exit_status, :line, args: args]
      )
  end
end
