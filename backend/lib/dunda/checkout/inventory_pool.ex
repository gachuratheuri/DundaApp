defmodule Dunda.Checkout.InventoryPool do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "inventory_pools" do
    field :pool_key, :string
    field :capacity, :integer
    field :reserved, :integer, default: 0
    field :sold, :integer, default: 0
    field :version, :integer, default: 1
    belongs_to :event, Dunda.Events.Event
    belongs_to :ticket_tier, Dunda.Ticketing.TicketTier
    has_many :reservations, Dunda.Checkout.InventoryReservation
    timestamps()
  end

  def changeset(pool, attrs) do
    pool
    |> cast(attrs, [:pool_key, :capacity, :reserved, :sold, :version, :event_id, :ticket_tier_id])
    |> validate_required([:pool_key, :capacity, :reserved, :sold, :version, :event_id])
    |> validate_number(:capacity, greater_than: 0)
    |> validate_number(:reserved, greater_than_or_equal_to: 0)
    |> validate_number(:sold, greater_than_or_equal_to: 0)
    |> validate_number(:version, greater_than: 0)
    |> assoc_constraint(:event)
    |> assoc_constraint(:ticket_tier)
    |> unique_constraint(:pool_key)
    |> validate_capacity_conservation()
  end

  defp validate_capacity_conservation(changeset) do
    capacity = get_field(changeset, :capacity)
    reserved = get_field(changeset, :reserved)
    sold = get_field(changeset, :sold)

    if Enum.all?([capacity, reserved, sold], &is_integer/1) and reserved + sold > capacity,
      do: add_error(changeset, :reserved, "reserved plus sold cannot exceed capacity"),
      else: changeset
  end
end
