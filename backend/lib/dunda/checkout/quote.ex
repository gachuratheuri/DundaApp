defmodule Dunda.Checkout.Quote do
  @moduledoc "Immutable, server-priced checkout quote with bounded lifetime."
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @statuses ~w(active consumed expired cancelled)

  schema "quotes" do
    field :quantity, :integer
    field :unit_price_cents, :integer
    field :fee_cents, :integer, default: 0
    field :total_cents, :integer
    field :currency, :string
    field :price_version, :string
    field :signature, :string
    field :status, :string, default: "active"
    field :expires_at, :utc_datetime
    field :consumed_at, :utc_datetime
    belongs_to :user, Dunda.Accounts.User
    belongs_to :event, Dunda.Events.Event
    belongs_to :ticket_tier, Dunda.Ticketing.TicketTier
    timestamps()
  end

  def changeset(quote, attrs) do
    quote
    |> cast(attrs, [
      :quantity,
      :unit_price_cents,
      :fee_cents,
      :total_cents,
      :currency,
      :price_version,
      :signature,
      :status,
      :expires_at,
      :consumed_at,
      :user_id,
      :event_id,
      :ticket_tier_id
    ])
    |> validate_required([
      :quantity,
      :unit_price_cents,
      :fee_cents,
      :total_cents,
      :currency,
      :price_version,
      :signature,
      :status,
      :expires_at,
      :user_id,
      :event_id
    ])
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:unit_price_cents, greater_than: 0)
    |> validate_number(:fee_cents, greater_than_or_equal_to: 0)
    |> validate_number(:total_cents, greater_than: 0)
    |> validate_inclusion(:status, @statuses)
    |> assoc_constraint(:user)
    |> assoc_constraint(:event)
    |> assoc_constraint(:ticket_tier)
    |> validate_total()
  end

  defp validate_total(changeset) do
    quantity = get_field(changeset, :quantity)
    unit = get_field(changeset, :unit_price_cents)
    fee = get_field(changeset, :fee_cents)
    total = get_field(changeset, :total_cents)

    if Enum.all?([quantity, unit, fee, total], &is_integer/1) and total != unit * quantity + fee,
      do: add_error(changeset, :total_cents, "must equal quantity × unit price + fee"),
      else: changeset
  end
end
