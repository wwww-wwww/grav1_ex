defmodule Grav1.Project do
  use Ecto.Schema
  import Ecto.Changeset

  schema "projects" do
    field :input, :string
    field :encoder, Grav1.Encoder
    field :priority, :integer, default: 0

    field :input_frames, :integer

    field :encoder_params, :string
    field :ffmpeg_params, :string

    field :split_min_frames, :integer, default: nil
    field :split_max_frames, :integer, default: nil

    field :grain_tables, :boolean, default: false

    has_many :segments, Grav1.Segment

    timestamps()
  end

  @doc false
  def changeset(user, attrs \\ %{}) do
    user
    |> cast(attrs, [:input, :encoder, :priority, :encoder_params, :ffmpeg_params, :split_min_frames, :split_max_frames, :grain_tables])
    |> validate_required([:input, :encoder, :encoder_params, :ffmpeg_params])
  end
end
