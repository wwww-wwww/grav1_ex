defmodule Grav1.Presence do
  use Phoenix.Presence,
    otp_app: :grav1,
    pubsub_server: Grav1.PubSub

  def fetch(topic, presences) do
    for {key, %{metas: metas}} <- presences, into: %{} do
      case key do
        "$" <> id ->
          {key, %{metas: metas, member: false, id: id}}

        username ->
          user = Grav1.Repo.get(Grav1.User, username)
            {key, %{metas: metas, member: true, username: user.username, name: user.name}}
      end
    end
  end
end
