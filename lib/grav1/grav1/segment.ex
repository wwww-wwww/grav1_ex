defmodule Grav1.Segment do
  use Ecto.Schema
  import Ecto.Changeset

  schema "segments" do
    field :n, :integer
    field :file, :string
    field :start, :integer
    field :frames, :integer
    field :filesize, :integer, default: 0

    belongs_to :project, Grav1.Project

    timestamps()
  end

  @doc false
  def changeset(user, attrs \\ %{}) do
    user
    |> cast(attrs, [:file, :start, :frames, :n, :filesize])
    |> validate_required([:file, :start, :frames, :n])
  end
end
