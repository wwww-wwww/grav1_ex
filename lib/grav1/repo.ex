defmodule Grav1.Repo do
  use Ecto.Repo,
    otp_app: :grav1,
    adapter: Ecto.Adapters.Postgres
end
