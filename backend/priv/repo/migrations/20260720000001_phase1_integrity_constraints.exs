defmodule Dunda.Repo.Migrations.Phase1IntegrityConstraints do
  use Ecto.Migration

  @moduledoc """
  Phase 1 integrity constraints for authoritative billing and exactly-once
  fulfilment. The ticket key migration refuses to proceed when existing data
  already violates the invariant; operators must reconcile such data first.
  """

  def up do
    alter table(:orders) do
      add :ticket_tier_id, references(:ticket_tiers, on_delete: :nilify_all)
      add :idempotency_key, :string
      add :redirect_url, :text
    end

    alter table(:payouts) do
      add :idempotency_key, :string
    end

    create unique_index(:payouts, [:idempotency_key],
             where: "idempotency_key IS NOT NULL",
             name: :payouts_idempotency_key_index
           )

    create index(:orders, [:ticket_tier_id])

    create unique_index(:orders, [:user_id, :idempotency_key],
             where: "user_id IS NOT NULL AND idempotency_key IS NOT NULL",
             name: :orders_user_id_idempotency_key_index
           )

    invalid_orders =
      repo().query!("""
      SELECT id FROM orders
      WHERE amount_cents <= 0 OR quantity <= 0
      LIMIT 20
      """).rows

    if invalid_orders != [] do
      raise "orders violate Phase 1 amount/quantity invariants: #{inspect(invalid_orders)}"
    end

    create constraint(:orders, :orders_amount_positive, check: "amount_cents > 0")
    create constraint(:orders, :orders_quantity_positive, check: "quantity > 0")

    alter table(:tickets) do
      add :fulfillment_key, :string
    end

    create unique_index(:tickets, [:fulfillment_key],
             where: "fulfillment_key IS NOT NULL",
             name: :tickets_fulfillment_key_index
           )
  end

  def down do
    drop_if_exists index(:payouts, [:idempotency_key], name: :payouts_idempotency_key_index)
    alter table(:payouts), do: remove(:idempotency_key)

    drop_if_exists index(:tickets, [:fulfillment_key], name: :tickets_fulfillment_key_index)
    alter table(:tickets), do: remove(:fulfillment_key)

    drop_if_exists constraint(:orders, :orders_amount_positive)
    drop_if_exists constraint(:orders, :orders_quantity_positive)
    drop_if_exists index(:orders, [:user_id, :idempotency_key], name: :orders_user_id_idempotency_key_index)
    drop_if_exists index(:orders, [:ticket_tier_id])
    alter table(:orders) do
      remove :redirect_url
      remove :idempotency_key
      remove :ticket_tier_id
    end
  end
end
