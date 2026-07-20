defmodule Dunda.Billing.Order do
  @moduledoc """
  A consumer Pesapal order. `merchant_reference` is our idempotent identity sent
  to Pesapal; `order_tracking_id` is Pesapal's identity returned on submit and
  echoed back on the IPN. Payout grouping uses `organisation_id`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @statuses ~w(pending completed failed invalid refunded partially_refunded manual_review)
  @payout_statuses ~w(unpaid queued paid)
  @kinds ~w(primary resale)
  @refund_statuses ~w(none pending submitted succeeded failed manual_review)

  schema "orders" do
    field :merchant_reference, :string
    field :order_tracking_id, :string

    field :amount_cents, :integer
    field :currency, :string, default: "KES"
    field :quantity, :integer, default: 1
    field :phone, :string
    field :idempotency_key, :string
    field :redirect_url, :string

    field :status, :string, default: "pending"
    field :kind, :string, default: "primary"
    field :resale_listing_id, :binary_id
    field :refund_status, :string, default: "none"
    field :refunded_amount_cents, :integer, default: 0
    field :refunded_at, :utc_datetime
    field :payout_status, :string, default: "unpaid"
    field :pesapal_status, :string

    belongs_to :event, Dunda.Events.Event
    belongs_to :ticket_tier, Dunda.Ticketing.TicketTier
    belongs_to :organisation, Dunda.Organisations.Organisation
    belongs_to :user, Dunda.Accounts.User
    belongs_to :resale_listing, Dunda.Market.Listing, type: :binary_id

    has_many :refunds, Dunda.Billing.Refund
    has_many :payout_items, Dunda.Organisations.PayoutItem

    timestamps()
  end

  @spec create_changeset(t(), map()) :: Ecto.Changeset.t()
  def create_changeset(order, attrs) do
    order
    |> cast(attrs, [
      :merchant_reference,
      :amount_cents,
      :currency,
      :quantity,
      :phone,
      :event_id, :ticket_tier_id, :idempotency_key,
      :organisation_id, :kind, :resale_listing_id,
      :user_id
    ])
    |> validate_required([:merchant_reference, :amount_cents, :event_id])
    |> validate_number(:amount_cents, greater_than: 0)
    |> validate_number(:quantity, greater_than: 0)
    |> validate_length(:idempotency_key, min: 16, max: 200)
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:refund_status, @refund_statuses)
    |> validate_number(:refunded_amount_cents, greater_than_or_equal_to: 0)
    |> validate_resale_link()
    |> unique_constraint(:merchant_reference)
    |> unique_constraint([:user_id, :idempotency_key], name: :orders_user_id_idempotency_key_index)
  end

  @spec status_changeset(t(), map()) :: Ecto.Changeset.t()
  def status_changeset(order, attrs) do
    order
    |> cast(attrs, [
      :order_tracking_id, :status, :kind, :resale_listing_id, :refund_status,
      :refunded_amount_cents, :refunded_at, :payout_status, :pesapal_status, :redirect_url
    ])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:refund_status, @refund_statuses)
    |> validate_inclusion(:payout_status, @payout_statuses)
    |> unique_constraint(:order_tracking_id)
    |> validate_state_transition()
  end

  defp validate_resale_link(changeset) do
    kind = get_field(changeset, :kind)
    listing_id = get_field(changeset, :resale_listing_id)

    cond do
      kind == "primary" and is_nil(listing_id) -> changeset
      kind == "resale" and not is_nil(listing_id) -> changeset
      true -> add_error(changeset, :resale_listing_id, "must match order kind")
    end
  end

  defp validate_state_transition(changeset) do
    case get_change(changeset, :status) do
      nil -> changeset
      next ->
        current = changeset.data.status || "pending"
        allowed = %{
          "pending" => ~w(pending completed failed invalid manual_review),
          "completed" => ~w(completed partially_refunded refunded manual_review),
          "partially_refunded" => ~w(partially_refunded refunded manual_review),
          "failed" => ~w(failed manual_review),
          "invalid" => ~w(invalid manual_review),
          "refunded" => ~w(refunded),
          # A verified refund result is an explicit compensating transition
          # out of manual review; ordinary callbacks cannot bypass this state.
          "manual_review" => ~w(manual_review partially_refunded refunded)
        }

        if next in Map.get(allowed, current, []), do: changeset, else: add_error(changeset, :status, "invalid monotonic state transition")
    end
  end
end
