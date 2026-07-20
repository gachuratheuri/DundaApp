defmodule Dunda.Checkout.JournalLine do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "journal_lines" do
    field :debit_cents, :integer, default: 0
    field :credit_cents, :integer, default: 0
    field :currency, :string
    field :metadata, :map, default: %{}
    belongs_to :journal_transaction, Dunda.Checkout.JournalTransaction
    belongs_to :account, Dunda.Checkout.Account
    timestamps(updated_at: false)
  end
  def changeset(line, attrs) do
    line
    |> cast(attrs, [:journal_transaction_id, :account_id, :debit_cents, :credit_cents, :currency, :metadata])
    |> validate_required([:journal_transaction_id, :account_id, :currency])
    |> validate_number(:debit_cents, greater_than_or_equal_to: 0)
    |> validate_number(:credit_cents, greater_than_or_equal_to: 0)
    |> validate_exactly_one_side()
    |> assoc_constraint(:journal_transaction)
    |> assoc_constraint(:account)
  end
  defp validate_exactly_one_side(changeset) do
    debit = get_field(changeset, :debit_cents) || 0
    credit = get_field(changeset, :credit_cents) || 0
    if (debit > 0 and credit == 0) or (credit > 0 and debit == 0), do: changeset, else: add_error(changeset, :debit_cents, "exactly one of debit_cents or credit_cents must be positive")
  end
end
