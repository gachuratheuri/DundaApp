defmodule Dunda.Checkout.Journal do
  @moduledoc "Append-only balanced journal writer; account balances are projections."
  import Ecto.Query, only: [from: 2]
  alias Dunda.Checkout.{Account, AccountBalance, JournalLine, JournalTransaction}
  alias Dunda.Repo

  @spec post!(String.t(), String.t(), [{String.t(), :debit | :credit, pos_integer()}], map()) ::
          JournalTransaction.t()
  def post!(reference, currency, lines, metadata \\ %{}) do
    if lines == [] or
         Enum.any?(lines, fn {_, side, amount} ->
           side not in [:debit, :credit] or not is_integer(amount) or amount <= 0
         end),
       do: raise(ArgumentError, "journal lines must be positive debit/credit amounts")

    debit_total =
      lines
      |> Enum.filter(&(elem(&1, 1) == :debit))
      |> Enum.reduce(0, fn {_, _, amount}, acc -> acc + amount end)

    credit_total =
      lines
      |> Enum.filter(&(elem(&1, 1) == :credit))
      |> Enum.reduce(0, fn {_, _, amount}, acc -> acc + amount end)

    if debit_total <= 0 or debit_total != credit_total,
      do: raise(ArgumentError, "unbalanced journal #{reference}")

    case Repo.get_by(JournalTransaction, reference: reference) do
      %JournalTransaction{
        currency: ^currency,
        total_debits_cents: ^debit_total,
        total_credits_cents: ^credit_total
      } = existing ->
        existing

      %JournalTransaction{} ->
        raise ArgumentError, "journal idempotency reference reused with different economics"

      nil ->
        tx =
          Repo.insert!(
            %JournalTransaction{}
            |> JournalTransaction.changeset(%{
              reference: reference,
              currency: currency,
              total_debits_cents: debit_total,
              total_credits_cents: credit_total,
              metadata: metadata
            })
          )

        Enum.each(lines, fn {account_code, side, amount} ->
          account = account_for!(account_code, currency)

          attrs = %{
            journal_transaction_id: tx.id,
            account_id: account.id,
            currency: currency,
            debit_cents: if(side == :debit, do: amount, else: 0),
            credit_cents: if(side == :credit, do: amount, else: 0),
            metadata: metadata
          }

          Repo.insert!(%JournalLine{} |> JournalLine.changeset(attrs))
          update_balance(account.id, currency, if(side == :debit, do: amount, else: -amount))
        end)

        tx
    end
  end

  defp account_for!(code, currency) do
    case Repo.one(from a in Account, where: a.code == ^code and a.currency == ^currency) do
      %Account{} = account ->
        account

      nil ->
        inserted =
          Repo.insert!(
            %Account{
              code: code,
              kind: account_kind(code),
              currency: currency,
              active: true
            },
            on_conflict: :nothing,
            conflict_target: [:code, :currency]
          )

        case inserted do
          %Account{id: nil} -> Repo.get_by!(Account, code: code, currency: currency)
          account -> account
        end
    end
  end

  defp update_balance(account_id, currency, delta) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert(
      %AccountBalance{
        account_id: account_id,
        currency: currency,
        balance_cents: delta,
        updated_at: now
      },
      on_conflict: [inc: [balance_cents: delta], set: [updated_at: now]],
      conflict_target: [:account_id, :currency]
    )
  end

  defp account_kind("provider_clearing"), do: "asset"
  defp account_kind("cash"), do: "asset"
  defp account_kind("customer_suspense"), do: "liability"
  defp account_kind("organiser_payable"), do: "liability"
  defp account_kind("refund_payable"), do: "liability"
  defp account_kind("platform_fee_revenue"), do: "revenue"
  defp account_kind(_), do: "control"
end
