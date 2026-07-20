defmodule Dunda.Checkout.PaymentIntent do
  @moduledoc "Provider-neutral payment intent and monotonic checkout state."
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @states ~w(created inventory_reserved provider_submission_pending provider_pending confirmed fulfilled failed expired_pending_reconciliation confirmed_late manual_review refund_pending refunded)

  schema "payment_intents" do
    field :quantity, :integer
    field :amount_cents, :integer
    field :currency, :string
    field :phone, :string
    field :idempotency_key, :string
    field :state, :string, default: "created"
    field :provider, :string
    field :provider_checkout_id, :string
    field :redirect_url, :string
    field :provider_receipt, :string
    field :failure_reason, :string
    field :manual_review_reason, :string
    field :expires_at, :utc_datetime
    field :confirmed_at, :utc_datetime
    field :fulfilled_at, :utc_datetime
    field :version, :integer, default: 1
    belongs_to :quote, Dunda.Checkout.Quote
    belongs_to :user, Dunda.Accounts.User
    belongs_to :event, Dunda.Events.Event
    belongs_to :ticket_tier, Dunda.Ticketing.TicketTier
    has_many :attempts, Dunda.Checkout.PaymentAttempt
    has_many :reservations, Dunda.Checkout.InventoryReservation
    has_many :line_items, Dunda.Checkout.PaymentLineItem
    timestamps()
  end

  def changeset(intent, attrs) do
    intent
    |> cast(attrs, [:quote_id, :user_id, :event_id, :ticket_tier_id, :quantity, :amount_cents, :currency, :phone, :idempotency_key, :state, :provider, :provider_checkout_id, :redirect_url, :provider_receipt, :failure_reason, :manual_review_reason, :expires_at, :confirmed_at, :fulfilled_at, :version])
    |> validate_required([:quote_id, :user_id, :event_id, :quantity, :amount_cents, :currency, :phone, :idempotency_key, :state, :expires_at, :version])
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:amount_cents, greater_than: 0)
    |> validate_number(:version, greater_than: 0)
    |> validate_inclusion(:state, @states)
    |> validate_length(:idempotency_key, min: 16, max: 200)
    |> assoc_constraint(:quote)
    |> assoc_constraint(:user)
    |> assoc_constraint(:event)
    |> assoc_constraint(:ticket_tier)
    |> unique_constraint(:provider_checkout_id)
    |> unique_constraint(:provider_receipt)
    |> validate_transition()
  end

  defp validate_transition(changeset) do
    case get_change(changeset, :state) do
      nil -> changeset
      next ->
        current = changeset.data.state || "created"
        allowed = %{
          "created" => ~w(created inventory_reserved failed manual_review),
          "inventory_reserved" => ~w(inventory_reserved provider_submission_pending failed expired_pending_reconciliation manual_review),
          "provider_submission_pending" => ~w(provider_submission_pending provider_pending failed manual_review),
          "provider_pending" => ~w(provider_pending confirmed failed expired_pending_reconciliation confirmed_late manual_review refund_pending),
          "confirmed" => ~w(confirmed fulfilled refund_pending manual_review),
          "fulfilled" => ~w(fulfilled refund_pending refunded manual_review),
          "failed" => ~w(failed manual_review),
          "expired_pending_reconciliation" => ~w(expired_pending_reconciliation confirmed_late manual_review refund_pending),
          "confirmed_late" => ~w(confirmed_late fulfilled refund_pending manual_review),
          "manual_review" => ~w(manual_review confirmed_late refund_pending refunded),
          "refund_pending" => ~w(refund_pending refunded manual_review),
          "refunded" => ~w(refunded)
        }
        if next in Map.get(allowed, current, []), do: changeset, else: add_error(changeset, :state, "invalid monotonic payment transition")
    end
  end
end
