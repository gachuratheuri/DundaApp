defmodule Dunda.Ledger.Transfer do
  @moduledoc """
  Append-only record of internal money movement between accounts (e.g. crediting
  a seller's wallet after a resale purchase).

  Like `Dunda.Ledger.Entry`, transfers are immutable: corrections are made by
  appending a compensating transfer, never by mutating a row. `reference` is the
  idempotency key so a replayed business event records exactly once.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "ledger_transfers" do
    field :from_account, :string
    field :to_account, :string
    field :amount_cents, :integer
    field :reference, :string
    timestamps(updated_at: false)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(transfer, attrs) do
    transfer
    |> cast(attrs, [:from_account, :to_account, :amount_cents, :reference])
    |> validate_required([:from_account, :to_account, :amount_cents, :reference])
    |> validate_number(:amount_cents, greater_than: 0)
    |> unique_constraint(:reference)
  end
end
