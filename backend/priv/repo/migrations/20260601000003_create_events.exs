defmodule Dunda.Repo.Migrations.CreateEvents do
  use Ecto.Migration

  def change do
    create table(:events) do
      add :name, :string, null: false
      add :venue, :string, null: false
      add :starts_at, :utc_datetime, null: false
      add :price_cents, :integer, null: false
      add :capacity, :integer, null: false
      timestamps()
    end

    create index(:events, [:starts_at])
  end
end
