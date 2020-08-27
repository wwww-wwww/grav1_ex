defmodule Grav1.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      Grav1.Repo,
      Grav1Web.Telemetry,
      Grav1Web.Counter,
      {Phoenix.PubSub, name: Grav1.PubSub},
      Grav1.WorkerAgent,
      Grav1Web.Endpoint,
      Grav1.Projects,
      Grav1.ProjectsExecutor
    ]

    opts = [strategy: :one_for_one, name: Grav1.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    Grav1Web.Endpoint.config_change(changed, removed)
    :ok
  end
end
