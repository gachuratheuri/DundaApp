defmodule Dunda.Ledger.Entry do
  @moduledoc """
  Append-only ledger entry recording the settlement of a payment transaction.

  The ledger is the system of record for money movement and is intentionally
  immutable — corrections are made by appending compensating entries, never by
  mutating an existing row. Retained for 7 years per CBK requirements.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "ledger_entries" do
    field :transaction_id, :string
    field :mpesa_receipt, :string
    field :amount_cents, :integer
    field :status, :string, default: "settled"
    timestamps(updated_at: false)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:transaction_id, :mpesa_receipt, :amount_cents, :status])
    |> validate_required([:transaction_id, :mpesa_receipt])
    |> unique_constraint(:mpesa_receipt)
    |> unique_constraint(:transaction_id)
  end
end
