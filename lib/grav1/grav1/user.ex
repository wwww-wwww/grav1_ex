defmodule Grav1.User do
  use Ecto.Schema
  import Ecto.Changeset
  alias Grav1.Repo

  @key_length 32

  @primary_key false
  schema "users" do
    field :username, :string, size: 32, primary_key: true
    field :name, :string, size: 32
    field :password, :string
    field :level, :integer, default: 0

    field :key, :string

    timestamps()
  end

  @doc false
  def changeset(user, attrs \\ %{}) do
    user
    |> cast(attrs, [:username, :password])
    |> validate_required([:username, :password])
    |> validate_changeset
    |> copy_username
    |> put_key
    |> generate_password_hash
  end

  defp validate_changeset(struct) do
    struct
    |> validate_length(:username, min: 1, max: 32)
    |> validate_format(:username, ~r/^[A-z0-9_-]+$/, [message: "Must consist only of letters, numbers, and - or _"])
    |> unique_constraint(:username, name: :users_pkey, message: "User with this username already exists")
    |> validate_length(:password, min: 6)
  end

  def generate_key() do
    key = :crypto.strong_rand_bytes(@key_length) |> Base.encode64 |> binary_part(0, @key_length)
    case Repo.get_by(Grav1.User, key: key) do
      nil ->
        key
      _ ->
        generate_key()
    end
  end
  
  def put_key(changeset) do
    case changeset do
      %Ecto.Changeset{valid?: true} ->
        put_change(changeset, :key, generate_key())
      _ ->
        changeset
    end
  end

  defp copy_username(changeset) do
    case changeset do
      %Ecto.Changeset{valid?: true, changes: %{username: username}} ->
        changeset
        |> put_change(:name, username)
        |> put_change(:username, username |> String.downcase())
      _ ->
        changeset
    end
  end

  defp generate_password_hash(changeset) do
    case changeset do
      %Ecto.Changeset{valid?: true, changes: %{password: password}} ->
        put_change(changeset, :password, Bcrypt.hash_pwd_salt(password))
      _ ->
        changeset
    end
  end
end
