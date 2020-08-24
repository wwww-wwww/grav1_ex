defmodule Grav1.Guardian do
  use Guardian,
    otp_app: :grav1

  def subject_for_token(user, _) do
    {:ok, user.username}
  end

  def resource_from_claims(claims) do
    user = Grav1.Repo.get(Grav1.User, claims["sub"])
    {:ok, user}
  end
end
