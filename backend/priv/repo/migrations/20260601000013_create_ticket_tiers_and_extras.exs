defmodule Dunda.Repo.Migrations.CreateTicketTiersAndExtras do
  @moduledoc """
  Persists the multi-tier inventory model that `EventEditorLive` and
  `EventDetailScreen` already present in the UI but that the reference schema
  collapsed into a single per-event tier.

  * `ticket_tiers` — one row per purchasable access level (Regular, VIP, …).
    `capacity` is the authoritative inventory size; live remaining counts stay
    in Redis keyed by tier id (`inventory:<tier_id>`), mirroring the existing
    `InventoryPoolServer` design but now at tier rather than event granularity.
  * `event_extras` — non-admission upsells (parking, merch, lockers) surfaced in
    the portal "Extras" step and the checkout upsell.
  """
  use Ecto.Migration

  def change do
    create table(:ticket_tiers) do
      add :event_id, references(:events, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :description, :text
      add :price_cents, :integer, null: false
      add :capacity, :integer, null: false
      # Lowest tier first in the EventDetail tier list.
      add :sort_order, :integer, null: false, default: 0
      add :is_vip, :boolean, null: false, default: false
      # on_sale -> paused -> sold_out -> closed.
      add :status, :string, null: false, default: "on_sale"
      # Optional per-purchase guardrail (anti-scalper).
      add :max_per_order, :integer, null: false, default: 10

      timestamps()
    end

    create index(:ticket_tiers, [:event_id])
    create unique_index(:ticket_tiers, [:event_id, :name])

    create constraint(:ticket_tiers, :ticket_tiers_price_non_negative, check: "price_cents >= 0")
    create constraint(:ticket_tiers, :ticket_tiers_capacity_non_negative, check: "capacity >= 0")
    create constraint(:ticket_tiers, :ticket_tiers_max_per_order_positive, check: "max_per_order > 0")

    create constraint(:ticket_tiers, :ticket_tiers_status_valid,
             check: "status IN ('on_sale', 'paused', 'sold_out', 'closed')"
           )

    create table(:event_extras) do
      add :event_id, references(:events, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :description, :text
      add :price_cents, :integer, null: false
      add :available, :boolean, null: false, default: true

      timestamps()
    end

    create index(:event_extras, [:event_id])

    create constraint(:event_extras, :event_extras_price_non_negative, check: "price_cents >= 0")
  end
end
