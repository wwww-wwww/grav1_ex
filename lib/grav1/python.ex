defmodule Grav1.Python do
  def create_port() do
    {:ok, port} =
      [
        python_path: Grav1.get_path(:python) |> String.to_charlist()
      ]
      |> :python.start()

    port
  end

  def call(port, module_name, func, args) do
    :python.call(port, :"helpers.#{module_name}", func, args)
  end
end
