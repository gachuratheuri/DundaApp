defmodule Dunda.Repo.Migrations.CreateTickets do
  use Ecto.Migration

  def change do
    create table(:tickets, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :nothing), null: false
      add :event_id, references(:events, on_delete: :nothing), null: false
      add :order_id, references(:orders, on_delete: :nothing)
      add :tier_label, :string, null: false
      add :price_kes, :integer, null: false
      add :status, :string, null: false, default: "valid"
      add :jwt, :text

      timestamps()
    end

    create index(:tickets, [:user_id])
    create index(:tickets, [:event_id])
    create index(:tickets, [:order_id])
  end
end
