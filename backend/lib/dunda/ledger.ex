defmodule Dunda.Ledger do
  @moduledoc """
  The financial ledger. Settling a transaction is idempotent on the M-Pesa
  receipt number so that a callback AND a dead-letter poll resolving the same
  payment can never double-credit.
  """
  import Ecto.Query, only: [from: 2]

  alias Dunda.Ledger.Entry
  alias Dunda.Ledger.Transfer
  alias Dunda.Repo

  @doc """
  Record the successful settlement of `transaction_id` against an M-Pesa
  `receipt`. Idempotent: a repeated receipt returns the existing entry.
  """
  @spec settle(String.t(), String.t(), keyword()) ::
          {:ok, Entry.t()} | {:error, Ecto.Changeset.t()}
  def settle(transaction_id, receipt, opts \\ []) do
    attrs = %{
      transaction_id: to_string(transaction_id),
      mpesa_receipt: receipt,
      amount_cents: Keyword.get(opts, :amount_cents),
      status: "settled"
    }

    %Entry{}
    |> Entry.changeset(attrs)
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: :mpesa_receipt
    )
    |> case do
      {:ok, %Entry{id: nil}} -> {:ok, get_by_receipt(receipt)}
      other -> other
    end
  end

  @doc """
  Record an internal account-to-account transfer (e.g. crediting a seller after
  a resale). Idempotent on `:reference` — replaying the same business event
  returns the existing transfer rather than double-crediting.
  """
  @spec record_transfer(map()) :: {:ok, Transfer.t()} | {:error, Ecto.Changeset.t()}
  def record_transfer(attrs) do
    %Transfer{}
    |> Transfer.changeset(attrs)
    |> Repo.insert(on_conflict: :nothing, conflict_target: :reference)
    |> case do
      {:ok, %Transfer{id: nil}} -> {:ok, get_transfer_by_reference(attrs)}
      other -> other
    end
  end

  defp get_transfer_by_reference(attrs) do
    reference = Map.get(attrs, :reference) || Map.get(attrs, "reference")
    Repo.get_by(Transfer, reference: reference)
  end

  @spec settled?(String.t()) :: boolean()
  def settled?(transaction_id) do
    Repo.exists?(
      from e in Entry,
        where: e.transaction_id == ^to_string(transaction_id) and e.status == "settled"
    )
  end

  defp get_by_receipt(receipt), do: Repo.get_by(Entry, mpesa_receipt: receipt)
end
