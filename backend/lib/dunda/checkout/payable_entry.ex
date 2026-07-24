defmodule Dunda.Checkout.PayableEntry do
  @moduledoc """
  Organisation- or seller-specific payable derived from a balanced journal
  transaction. This is the sole payout-selection authority.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @statuses ~w(payable queued paid refunded manual_review)
  @source_types ~w(payment_intent resale_order)

  schema "payable_entries" do
    field :source_type, :string
    field :source_id, :string
    field :amount_cents, :integer
    field :refunded_cents, :integer, default: 0
    field :currency, :string
    field :status, :string, default: "payable"
    field :paid_at, :utc_datetime
    field :manual_review_reason, :string

    belongs_to :journal_transaction, Dunda.Checkout.JournalTransaction, type: :binary_id
    belongs_to :organisation, Dunda.Organisations.Organisation
    belongs_to :beneficiary_user, Dunda.Accounts.User

    has_many :payout_items, Dunda.Organisations.PayoutItem
    timestamps()
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [
      :source_type,
      :source_id,
      :amount_cents,
      :refunded_cents,
      :currency,
      :status,
      :paid_at,
      :manual_review_reason,
      :journal_transaction_id,
      :organisation_id,
      :beneficiary_user_id
    ])
    |> validate_required([
      :source_type,
      :source_id,
      :amount_cents,
      :refunded_cents,
      :currency,
      :status,
      :journal_transaction_id
    ])
    |> validate_inclusion(:source_type, @source_types)
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:amount_cents, greater_than: 0)
    |> validate_number(:refunded_cents, greater_than_or_equal_to: 0)
    |> validate_beneficiary()
    |> validate_refund_total()
    |> assoc_constraint(:journal_transaction)
    |> assoc_constraint(:organisation)
    |> assoc_constraint(:beneficiary_user)
    |> unique_constraint([:source_type, :source_id],
      name: :payable_entries_source_unique
    )
  end

  def available_cents(%__MODULE__{} = entry),
    do: max(entry.amount_cents - entry.refunded_cents, 0)

  defp validate_beneficiary(changeset) do
    organisation_id = get_field(changeset, :organisation_id)
    user_id = get_field(changeset, :beneficiary_user_id)

    if (is_nil(organisation_id) and not is_nil(user_id)) or
         (not is_nil(organisation_id) and is_nil(user_id)),
       do: changeset,
       else: add_error(changeset, :organisation_id, "exactly one beneficiary is required")
  end

  defp validate_refund_total(changeset) do
    amount = get_field(changeset, :amount_cents)
    refunded = get_field(changeset, :refunded_cents)

    if is_integer(amount) and is_integer(refunded) and refunded <= amount,
      do: changeset,
      else: add_error(changeset, :refunded_cents, "cannot exceed payable amount")
  end
end
