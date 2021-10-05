import Config

# Configure your database
config :grav1, Grav1.Repo,
  username: "grav1",
  password: "grav1",
  database: "grav1",
  hostname: "192.168.1.51",
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

# For development, we disable any cache and enable
# debugging and code reloading.
#
# The watchers configuration can be used to run external
# watchers to your application. For example, we use it
# with esbuild to bundle .js and .css sources.
config :grav1, Grav1Web.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 6001],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "GZ3cwkU0Ro2EoeueWKy36R6CXbtgu0OPbr6f+GKofLUp3QSIennMOM6YIkbFz98L",
  watchers: [
    # Start the esbuild watcher by calling Esbuild.install_and_run(:default, args)
    esbuild: {Esbuild, :install_and_run, [:default, ~w(--sourcemap=inline --watch)]},
    sass: {
      DartSass,
      :install_and_run,
      [:default, ~w(--embed-source-map --source-map-urls=absolute --watch)]
    }
  ]

# Watch static and templates for browser reloading.
config :grav1, Grav1Web.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/gettext/.*(po)$",
      ~r"lib/grav1_web/(live|views)/.*(ex)$",
      ~r"lib/grav1_web/templates/.*(eex)$"
    ]
  ]

# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n"

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime
