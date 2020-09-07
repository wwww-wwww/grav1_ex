defmodule Grav1.RateLimit do
  use Agent

  def start_link(_) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  def can_execute?(key, rate) do
    Agent.get_and_update(__MODULE__, fn state ->
      case Map.get(state, key) do
        nil ->
          {true, Map.put(state, key, :os.system_time(:millisecond))}

        time ->
          current_time = :os.system_time(:millisecond)

          if current_time - time > rate * 1000 do
            {true, Map.put(state, key, current_time)}
          else
            {false, state}
          end
      end
    end)
  end
end
