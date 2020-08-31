defmodule Grav1.Repo.Migrations.CreateProjects do
  use Ecto.Migration

  def change do
    Grav1.Encoder.create_type()

    create table(:projects) do
      add :input, :string
      add :encoder, Grav1.Encoder.type()
      add :priority, :integer, default: 0
  
      add :input_frames, :integer
  
      add :encoder_params, {:array, :string}
      add :ffmpeg_params, {:array, :string}
  
      add :split_min_frames, :integer, default: nil
      add :split_max_frames, :integer, default: nil
  
      add :grain_tables, :boolean, default: false

      timestamps()
    end
  end
end
