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
      Grav1.RateLimit,
      Grav1.VerificationQueue,
      Grav1.VerificationExecutor,
      Grav1.ActionsQueue,
      Grav1.Actions,
      Grav1.ProjectsExecutorQueue,
      Grav1.ProjectsExecutor,
      Grav1.Projects
    ]

    get_version(
      :ffmpeg,
      Application.fetch_env!(:grav1, :path_ffmpeg),
      ["-version"],
      ~r/ffmpeg version (.+?) /
    )

    get_version(
      :aomenc,
      Application.fetch_env!(:grav1, :path_aomenc),
      ["--help"],
      ~r/AOMedia Project AV1 Encoder (.+?) /
    )

    get_version(
      :vpxenc,
      Application.fetch_env!(:grav1, :path_vpxenc),
      ["--help"],
      ~r/WebM Project VP9 Encoder (.+?) /
    )

    get_version(:dav1d, Application.fetch_env!(:grav1, :path_dav1d), ["-v"], ~r/([^\r\n]+)/)
    get_version(:python, Application.fetch_env!(:grav1, :path_python), ["-V"], ~r/([^\r\n]+)/)
    get_version(:mkvmerge, Application.fetch_env!(:grav1, :path_mkvmerge), ["-V"], ~r/([^\r\n]+)/)

    get_version(
      :vapoursynth,
      Application.fetch_env!(:grav1, :path_python),
      ["-u", "helpers/vs_version.py"],
      ~r/([^\r\n]+)/
    )

    case File.ls("actions") do
      {:ok, files} ->
        files = Enum.map(files, &Path.join("actions", &1))
        Application.put_env(:on_complete_actions, :actions, files)

      _ ->
        Application.put_env(:on_complete_actions, :actions, [])
    end

    opts = [strategy: :one_for_one, name: Grav1.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def get_version(key, executable, args, re) do
    version =
      case System.cmd(executable, args, stderr_to_stdout: true) do
        {resp, 0} ->
          case Regex.run(re, resp) do
            nil -> :error
            [_, version] -> version
          end

        _ ->
          nil
      end

    Application.put_env(:versions, key, version)
    version
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    Grav1Web.Endpoint.config_change(changed, removed)
    :ok
  end
end
