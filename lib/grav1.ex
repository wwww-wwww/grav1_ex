defmodule Grav1 do
  def get_path(key) do
    Application.fetch_env!(:grav1, :paths)[key]
  end
end
