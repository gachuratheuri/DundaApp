defmodule Dunda.Billing.Refund do
  @moduledoc "Durable refund intent and provider reconciliation state."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @type t :: %__MODULE__{}
  @statuses ~w(pending submitted succeeded failed manual_review)

  schema "refunds" do
    field :amount_cents, :integer
    field :currency, :string, default: "KES"
    field :status, :string, default: "pending"
    field :reason, :string
    field :idempotency_key, :string
    field :provider_reference, :string
    field :failure_reason, :string
    field :submitted_at, :utc_datetime
    field :completed_at, :utc_datetime

    belongs_to :order, Dunda.Billing.Order
    belongs_to :ticket, Dunda.Ticketing.Ticket, type: :binary_id
    belongs_to :requested_by, Dunda.Accounts.User, foreign_key: :requested_by_id

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(refund, attrs) do
    refund
    |> cast(attrs, [
      :amount_cents,
      :currency,
      :status,
      :reason,
      :idempotency_key,
      :provider_reference,
      :failure_reason,
      :submitted_at,
      :completed_at,
      :order_id,
      :ticket_id,
      :requested_by_id
    ])
    |> validate_required([:amount_cents, :currency, :status, :reason, :idempotency_key, :order_id])
    |> validate_number(:amount_cents, greater_than: 0)
    |> validate_inclusion(:status, @statuses)
    |> validate_length(:reason, min: 3, max: 500)
    |> validate_length(:idempotency_key, min: 8, max: 255)
    |> assoc_constraint(:order)
    |> unique_constraint(:idempotency_key)
    |> unique_constraint(:provider_reference)
    |> validate_transition()
  end

  defp validate_transition(changeset) do
    case get_change(changeset, :status) do
      nil ->
        changeset

      next ->
        current = changeset.data.status || "pending"

        allowed = %{
          "pending" => ~w(pending submitted failed manual_review),
          "submitted" => ~w(submitted succeeded failed manual_review),
          "succeeded" => ~w(succeeded),
          "failed" => ~w(failed manual_review),
          "manual_review" => ~w(manual_review succeeded failed)
        }

        if next in Map.get(allowed, current, []),
          do: changeset,
          else: add_error(changeset, :status, "invalid monotonic refund transition")
    end
  end
end
