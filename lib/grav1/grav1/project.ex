defmodule Grav1.Project do
  use Ecto.Schema
  import Ecto.Changeset

  import EctoEnum

  defenum State, idle: 0, ready: 1, completed: 2

  schema "projects" do
    field :input, :string
    field :name, :string, default: nil
    field :priority, :integer, default: 0

    field :input_frames, :integer

    field :encoder, Grav1.Encoder

    field :encoder_params, {:array, :string}
    field :ffmpeg_params, {:array, :string}

    field :split_min_frames, :integer, default: nil
    field :split_max_frames, :integer, default: nil

    field :grain_tables, :boolean, default: false

    field :state, State

    field :status, :string, default: "", virtual: true
    field :progress, :float, default: nil, virtual: true
    field :log, {:array, :string}, default: [], virtual: true

    has_many :segments, Grav1.Segment

    timestamps()
  end

  @doc false
  def changeset(user, attrs \\ %{}) do
    user
    |> cast(attrs, [:input, :name, :encoder, :priority, :encoder_params, :ffmpeg_params, :split_min_frames, :split_max_frames, :grain_tables])
    |> validate_required([:input, :encoder, :encoder_params, :ffmpeg_params])
  end
end
