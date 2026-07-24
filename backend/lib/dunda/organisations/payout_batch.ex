defmodule Dunda.Organisations.PayoutBatch do
  @moduledoc "Immutable selection boundary for an organiser payout attempt."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @type t :: %__MODULE__{}
  @statuses ~w(pending submitting submitted paid failed manual_review)

  schema "payout_batches" do
    field :amount_cents, :integer
    field :currency, :string, default: "KES"
    field :status, :string, default: "pending"
    field :idempotency_key, :string
    field :b2c_conversation_id, :string
    field :b2c_receipt, :string
    field :failure_reason, :string
    field :period_start, :utc_datetime
    field :period_end, :utc_datetime
    field :submission_started_at, :utc_datetime
    field :submitted_at, :utc_datetime
    field :paid_at, :utc_datetime

    belongs_to :organisation, Dunda.Organisations.Organisation
    belongs_to :beneficiary_user, Dunda.Accounts.User
    has_many :items, Dunda.Organisations.PayoutItem

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(batch, attrs) do
    batch
    |> cast(attrs, [
      :amount_cents,
      :currency,
      :status,
      :idempotency_key,
      :b2c_conversation_id,
      :b2c_receipt,
      :failure_reason,
      :period_start,
      :period_end,
      :submitted_at,
      :paid_at,
      :submission_started_at,
      :organisation_id,
      :beneficiary_user_id
    ])
    |> validate_required([:amount_cents, :currency, :status, :idempotency_key])
    |> validate_number(:amount_cents, greater_than: 0)
    |> validate_inclusion(:status, @statuses)
    |> validate_length(:idempotency_key, min: 8, max: 255)
    |> assoc_constraint(:organisation)
    |> assoc_constraint(:beneficiary_user)
    |> validate_beneficiary()
    |> unique_constraint(:idempotency_key)
    |> unique_constraint(:b2c_conversation_id)
    |> validate_transition()
  end

  defp validate_beneficiary(changeset) do
    organisation_id = get_field(changeset, :organisation_id)
    user_id = get_field(changeset, :beneficiary_user_id)

    if (organisation_id && is_nil(user_id)) || (user_id && is_nil(organisation_id)),
      do: changeset,
      else: add_error(changeset, :organisation_id, "exactly one beneficiary is required")
  end

  defp validate_transition(changeset) do
    case get_change(changeset, :status) do
      nil ->
        changeset

      next ->
        current = changeset.data.status || "pending"

        allowed = %{
          "pending" => ~w(pending submitting manual_review),
          "submitting" => ~w(submitting submitted manual_review),
          "submitted" => ~w(submitted paid failed manual_review),
          "paid" => ~w(paid),
          "failed" => ~w(failed manual_review),
          # An operator may apply a verified provider result after an
          # ambiguous submission; this is an explicit compensating transition,
          # not an automatic retry.
          "manual_review" => ~w(manual_review paid failed)
        }

        if next in Map.get(allowed, current, []),
          do: changeset,
          else: add_error(changeset, :status, "invalid monotonic payout transition")
    end
  end
end
