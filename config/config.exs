use Mix.Config

config :grav1,
  ecto_repos: [Grav1.Repo],
  encoders: [:aomenc, :vpxenc],
  paths: [
    ffmpeg: System.find_executable("ffmpeg"),
    aomenc: System.find_executable("aomenc"),
    vpxenc: System.find_executable("vpxenc"),
    dav1d: System.find_executable("dav1d"),
    vspipe: System.find_executable("vspipe"),
    python: System.find_executable("python"),
    mkvmerge: System.find_executable("mkvmerge"),
    mkvextract: System.find_executable("mkvextract"),
    aomenc_onepass_kf: System.find_executable("onepass_keyframes")
  ],
  path_projects: "projects",
  path_verification: "verification"

# Configures the endpoint
config :grav1, Grav1Web.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "+HkR7QSiAXWDhfxRGzEyQVvZQRJNHxgJqN8J06KURrqG7seAik9Z2zDdV8xs0AtC",
  render_errors: [view: Grav1Web.ErrorView, accepts: ~w(html json), layout: false],
  pubsub_server: Grav1.PubSub,
  live_view: [signing_salt: "nNb2S5Xn"]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id],
  level: :info

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"

config :grav1, Grav1.Guardian,
  issuer: "grav1",
  secret_key: "RV+mwteNk8/5tONMnHZoCH+piUX0izKBoBQvYs8D3gJ0su02O7erujgJ8pyqxpOd"
