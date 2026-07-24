defmodule Dunda.Ticketing.TicketTier do
  @moduledoc """
  A purchasable access level within an event (Regular, VIP, Early Bird, …).

  The tier is the unit of inventory. PostgreSQL `inventory_pools` rows are the
  authority for capacity, reservations, and sales; Redis may contain only a
  disposable remaining-count projection. `remaining` is populated from that
  authoritative state at read time and is never persisted on this schema.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @statuses ~w(on_sale paused sold_out closed)

  schema "ticket_tiers" do
    field :name, :string
    field :description, :string
    field :price_cents, :integer
    field :capacity, :integer
    field :sort_order, :integer, default: 0
    field :is_vip, :boolean, default: false
    field :status, :string, default: "on_sale"
    field :max_per_order, :integer, default: 10

    # Populated from authoritative inventory state at read time; not persisted.
    field :remaining, :integer, virtual: true

    belongs_to :event, Dunda.Events.Event

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(tier, attrs) do
    tier
    |> cast(attrs, [
      :name,
      :description,
      :price_cents,
      :capacity,
      :sort_order,
      :is_vip,
      :status,
      :max_per_order,
      :event_id
    ])
    |> validate_required([:name, :price_cents, :capacity, :event_id])
    |> validate_number(:price_cents, greater_than_or_equal_to: 0)
    |> validate_number(:capacity, greater_than_or_equal_to: 0)
    |> validate_number(:max_per_order, greater_than: 0)
    |> validate_inclusion(:status, @statuses)
    |> assoc_constraint(:event)
    |> unique_constraint([:event_id, :name])
  end
end
