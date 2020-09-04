defmodule Grav1.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :username, :string, size: 32, primary_key: true
      add :name, :string, size: 32
      add :password, :string
      add :level, :integer, default: 0

      add :key, :string

      timestamps()
    end
  end
end
