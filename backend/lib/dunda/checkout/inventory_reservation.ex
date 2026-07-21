defmodule Dunda.Checkout.InventoryReservation do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  @statuses ~w(active consumed released uncertain)
  schema "inventory_reservations" do
    field :quantity, :integer
    field :status, :string, default: "active"
    field :expires_at, :utc_datetime
    field :released_at, :utc_datetime
    field :consumed_at, :utc_datetime
    belongs_to :payment_intent, Dunda.Checkout.PaymentIntent, type: :binary_id
    belongs_to :inventory_pool, Dunda.Checkout.InventoryPool, type: :binary_id
    timestamps()
  end

  def changeset(reservation, attrs) do
    reservation
    |> cast(attrs, [
      :payment_intent_id,
      :inventory_pool_id,
      :quantity,
      :status,
      :expires_at,
      :released_at,
      :consumed_at
    ])
    |> validate_required([:payment_intent_id, :inventory_pool_id, :quantity, :status, :expires_at])
    |> validate_number(:quantity, greater_than: 0)
    |> validate_inclusion(:status, @statuses)
    |> assoc_constraint(:payment_intent)
    |> assoc_constraint(:inventory_pool)
  end
end
