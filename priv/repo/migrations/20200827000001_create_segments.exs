defmodule Grav1.Repo.Migrations.CreateSegments do
  use Ecto.Migration

  def change do
    create table(:segments) do
      add :n, :integer
      add :file, :string
      add :start, :integer
      add :frames, :integer
      add :filesize, :integer, default: 0

      add :project_id, references(:projects)

      timestamps()
    end
  end
end
