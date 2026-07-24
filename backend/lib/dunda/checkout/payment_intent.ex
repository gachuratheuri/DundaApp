defmodule Dunda.Checkout.PaymentIntent do
  @moduledoc "Provider-neutral payment intent and monotonic checkout state."
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @type t :: %__MODULE__{}
  @states ~w(created inventory_reserved provider_submission_pending provider_pending confirmed fulfilled failed expired_pending_reconciliation confirmed_late manual_review refund_pending refunded)

  # Single source of truth for the state machine's edges. Exposed via
  # `transition_allowed?/2` so callers that must react gracefully to "this
  # transition doesn't apply any more" (e.g. `Dunda.Checkout.fail_payment/2`
  # receiving a stale/reordered provider failure after the intent already
  # confirmed) can check the SAME graph `validate_transition/1` enforces,
  # rather than maintaining a second, driftable copy of it.
  @transitions %{
    "created" => ~w(created inventory_reserved failed manual_review),
    "inventory_reserved" =>
      ~w(inventory_reserved provider_submission_pending failed expired_pending_reconciliation manual_review),
    "provider_submission_pending" =>
      ~w(provider_submission_pending provider_pending failed manual_review),
    "provider_pending" =>
      ~w(provider_pending confirmed failed expired_pending_reconciliation confirmed_late manual_review refund_pending),
    "confirmed" => ~w(confirmed fulfilled refund_pending manual_review),
    "fulfilled" => ~w(fulfilled refund_pending manual_review),
    "failed" => ~w(failed manual_review),
    "expired_pending_reconciliation" =>
      ~w(expired_pending_reconciliation confirmed_late manual_review refund_pending),
    "confirmed_late" => ~w(confirmed_late fulfilled refund_pending manual_review),
    "manual_review" => ~w(manual_review confirmed_late refund_pending),
    "refund_pending" => ~w(refund_pending refunded manual_review),
    "refunded" => ~w(refunded)
  }

  @doc "Whether `to` is a legal next state from `from` in the payment-intent state machine."
  @spec transition_allowed?(String.t(), String.t()) :: boolean()
  def transition_allowed?(from, to), do: to in Map.get(@transitions, from, [])

  @doc false
  def states, do: @states

  @doc false
  def transitions, do: @transitions

  schema "payment_intents" do
    field :quantity, :integer
    field :amount_cents, :integer
    field :currency, :string
    # Checkout contact phone is encrypted at rest (Phase 11 data-governance
    # hardening); it was plaintext before `phase11_encrypt_contact_fields`.
    field :phone_encrypted, Dunda.Encrypted.Binary
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
    belongs_to :quote, Dunda.Checkout.Quote, type: :binary_id
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
    |> cast(attrs, [
      :quote_id,
      :user_id,
      :event_id,
      :ticket_tier_id,
      :quantity,
      :amount_cents,
      :currency,
      :phone_encrypted,
      :idempotency_key,
      :state,
      :provider,
      :provider_checkout_id,
      :redirect_url,
      :provider_receipt,
      :failure_reason,
      :manual_review_reason,
      :expires_at,
      :confirmed_at,
      :fulfilled_at,
      :version
    ])
    |> validate_required([
      :quote_id,
      :user_id,
      :event_id,
      :quantity,
      :amount_cents,
      :currency,
      :phone_encrypted,
      :idempotency_key,
      :state,
      :expires_at,
      :version
    ])
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
      nil ->
        changeset

      next ->
        current = changeset.data.state || "created"

        if transition_allowed?(current, next),
          do: changeset,
          else: add_error(changeset, :state, "invalid monotonic payment transition")
    end
  end
end
