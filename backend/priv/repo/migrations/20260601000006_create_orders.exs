defmodule Dunda.Repo.Migrations.CreateOrders do
  use Ecto.Migration

  def change do
    create table(:orders) do
      add :merchant_reference, :string, null: false
      add :order_tracking_id, :string

      add :amount_cents, :integer, null: false
      add :currency, :string, null: false, default: "KES"
      add :quantity, :integer, null: false, default: 1
      add :phone, :string

      add :status, :string, null: false, default: "pending"
      add :payout_status, :string, null: false, default: "unpaid"
      add :pesapal_status, :string

      add :event_id, references(:events, on_delete: :nilify_all)
      add :organisation_id, references(:organisations, on_delete: :nilify_all)
      add :user_id, references(:users, on_delete: :nilify_all)

      timestamps()
    end

    create unique_index(:orders, [:merchant_reference])
    create unique_index(:orders, [:order_tracking_id], where: "order_tracking_id IS NOT NULL")
    # Payout sweep scans completed+unpaid orders grouped by org.
    create index(:orders, [:organisation_id, :status, :payout_status])
  end
end
