defmodule Grav1.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @encoders [
    aomenc: {["--help"], ~r/AOMedia Project AV1 Encoder (.+?) /},
    vpxenc: {["--help"], ~r/WebM Project VP9 Encoder (.+?) /}
  ]

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

    paths = Application.fetch_env!(:grav1, :paths)

    get_version(:ffmpeg, paths[:ffmpeg], ["-version"], ~r/ffmpeg version (.+?) /)

    for encoder <- Application.fetch_env!(:grav1, :encoders) do
      {args, re} = @encoders[encoder]
      get_version(encoder, paths[encoder], args, re)
    end

    get_version(:dav1d, paths[:dav1d], ["-v"], ~r/([^\r\n]+)/)
    get_version(:python, paths[:python], ["-V"], ~r/([^\r\n]+)/)
    get_version(:mkvmerge, paths[:mkvmerge], ["-V"], ~r/([^\r\n]+)/)

    get_version(
      :vapoursynth,
      paths[:python],
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
