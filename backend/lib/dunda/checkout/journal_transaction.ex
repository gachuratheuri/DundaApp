defmodule Dunda.Checkout.JournalTransaction do
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "journal_transactions" do
    field :reference, :string
    field :currency, :string
    field :total_debits_cents, :integer, default: 0
    field :total_credits_cents, :integer, default: 0
    field :metadata, :map, default: %{}
    has_many :lines, Dunda.Checkout.JournalLine
    timestamps(updated_at: false)
  end
  def changeset(tx, attrs) do
    tx
    |> cast(attrs, [:reference, :currency, :total_debits_cents, :total_credits_cents, :metadata])
    |> validate_required([:reference, :currency, :total_debits_cents, :total_credits_cents])
    |> validate_number(:total_debits_cents, greater_than_or_equal_to: 0)
    |> validate_number(:total_credits_cents, greater_than_or_equal_to: 0)
    |> unique_constraint(:reference)
  end
end
