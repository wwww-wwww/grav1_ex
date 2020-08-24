defmodule Grav1.WorkerAgent do
  use Agent

  alias Grav1Web.Endpoint
  
  alias Grav1.{Repo, User}

  alias Phoenix.HTML

  defstruct workers: []

  def start_link(_) do
    Agent.start_link(fn -> %__MODULE__{} end, name: __MODULE__)
  end

  def chat(channel, socket, msg) do
    {:noreply}
  end
end
