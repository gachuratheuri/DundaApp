defmodule Dunda.Checkout.PaymentLineItem do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "payment_line_items" do
    field :line_number, :integer
    field :quantity, :integer
    field :unit_price_cents, :integer
    field :currency, :string
    field :price_version, :string
    belongs_to :payment_intent, Dunda.Checkout.PaymentIntent, type: :binary_id
    belongs_to :ticket_tier, Dunda.Ticketing.TicketTier
    has_one :ticket_batch, Dunda.Checkout.TicketBatch
    timestamps()
  end

  def changeset(line, attrs) do
    line
    |> cast(attrs, [
      :payment_intent_id,
      :line_number,
      :ticket_tier_id,
      :quantity,
      :unit_price_cents,
      :currency,
      :price_version
    ])
    |> validate_required([
      :payment_intent_id,
      :line_number,
      :quantity,
      :unit_price_cents,
      :currency,
      :price_version
    ])
    |> validate_number(:line_number, greater_than: 0)
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:unit_price_cents, greater_than: 0)
    |> assoc_constraint(:payment_intent)
    |> assoc_constraint(:ticket_tier)
    |> unique_constraint([:payment_intent_id, :line_number],
      name: :payment_line_items_intent_line_unique
    )
  end
end
