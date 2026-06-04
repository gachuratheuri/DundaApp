defmodule Dunda.Repo.Migrations.CreateResaleListings do
  use Ecto.Migration

  def change do
    create table(:resale_listings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :ticket_id, references(:tickets, type: :binary_id, on_delete: :nothing), null: false
      add :seller_id, references(:users, on_delete: :nothing), null: false
      add :asking_price_kes, :integer, null: false
      add :status, :string, null: false, default: "active"

      timestamps()
    end

    create index(:resale_listings, [:ticket_id])
    create index(:resale_listings, [:seller_id])
    create index(:resale_listings, [:status])
  end
end
