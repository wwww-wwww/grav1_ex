defmodule Grav1.Guardian do
  use Guardian,
    otp_app: :grav1

  @claims %{"typ" => "access"}
  @token_key "guardian_default_token"

  def subject_for_token(user, _) do
    {:ok, user.username}
  end

  def resource_from_claims(%{@token_key => token}) do
    case Guardian.decode_and_verify(Grav1.Guardian, token, @claims) do
      {:ok, claims} ->
        resource_from_claims(claims)

      _ ->
        {:error, "no_user"}
    end
  end

  def resource_from_claims(claims) do
    case Grav1.Repo.get(Grav1.User, claims["sub"]) do
      nil -> {:error, "no user"}
      user -> {:ok, user}
    end
  end
end
