defmodule Grav1.Python do
  def create_port() do
    {:ok, port} = 
      [
        python_path: Application.fetch_env!(:grav1, :path_python) |> String.to_charlist(),
        cd: "helpers" |> String.to_charlist
      ]
      |> :python.start()

    port
  end
end