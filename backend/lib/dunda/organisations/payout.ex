defmodule Dunda.Organisations.Payout do
  @moduledoc """
  A B2C payout attempt to an organisation. Destination data is encrypted at
  rest and is never copied into Phase 6 payout batches.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @statuses ~w(pending processing paid failed)

  schema "payouts" do
    field :amount_cents, :integer
    field :currency, :string, default: "KES"
    field :mpesa_phone_encrypted, Dunda.Encrypted.Binary
    field :mpesa_phone, :string, virtual: true
    field :status, :string, default: "pending"
    field :b2c_conversation_id, :string
    field :b2c_receipt, :string
    field :failure_reason, :string
    field :idempotency_key, :string
    field :period_start, :utc_datetime
    field :period_end, :utc_datetime
    field :paid_at, :utc_datetime

    belongs_to :organisation, Dunda.Organisations.Organisation

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(payout, attrs) do
    payout
    |> cast(attrs, [
      :amount_cents, :currency, :mpesa_phone_encrypted, :status, :b2c_conversation_id,
      :b2c_receipt, :failure_reason, :period_start, :period_end, :paid_at,
      :organisation_id, :idempotency_key
    ])
    |> validate_required([:amount_cents, :currency, :mpesa_phone_encrypted, :status, :organisation_id])
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:amount_cents, greater_than: 0)
    |> assoc_constraint(:organisation)
    |> unique_constraint(:b2c_conversation_id)
    |> unique_constraint(:idempotency_key, name: :payouts_idempotency_key_index)
  end
end
