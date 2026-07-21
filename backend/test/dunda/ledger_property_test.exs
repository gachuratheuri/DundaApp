defmodule Dunda.LedgerPropertyTest do
  @moduledoc """
  Property-based test of Invariant 4 from the root remediation plan: every
  journal transaction balances (`sum(debits) == sum(credits)`). Drives
  `Dunda.Checkout.Journal.post!/4` directly — the real production entry
  point used by settlement (`checkout.ex:261`), refunds, and payouts — not a
  reimplementation.
  """
  use Dunda.DataCase, async: true
  use ExUnitProperties

  alias Dunda.Checkout.{Journal, JournalLine, JournalTransaction}

  @accounts [
    "provider_clearing",
    "cash",
    "organiser_payable",
    "platform_fee_revenue",
    "refund_payable"
  ]

  defp account_generator, do: StreamData.member_of(@accounts)
  defp amount_generator, do: StreamData.integer(1..1_000_000)

  # Splits `total` into `n` positive integer parts summing back to `total`.
  # Requires total >= n (otherwise n positive parts cannot sum to total).
  defp split(total, 1), do: [total]

  defp split(total, n) do
    max_take = total - (n - 1)
    take = if max_take <= 1, do: 1, else: Enum.random(1..max_take)
    [take | split(total - take, n - 1)]
  end

  property "any balanced set of debit/credit lines posts successfully and the stored sums match" do
    check all(
            debit_count <- StreamData.integer(1..4),
            credit_count <- StreamData.integer(1..4),
            total <- StreamData.integer(max(debit_count, credit_count)..1_000_000),
            debit_accounts <- StreamData.list_of(account_generator(), length: debit_count),
            credit_accounts <- StreamData.list_of(account_generator(), length: credit_count),
            max_runs: 50
          ) do
      reference = "prop-ledger-#{System.unique_integer([:positive])}"

      debit_lines =
        debit_accounts
        |> Enum.zip(split(total, debit_count))
        |> Enum.map(fn {acc, amt} -> {acc, :debit, amt} end)

      credit_lines =
        credit_accounts
        |> Enum.zip(split(total, credit_count))
        |> Enum.map(fn {acc, amt} -> {acc, :credit, amt} end)

      tx = Journal.post!(reference, "KES", debit_lines ++ credit_lines, %{})

      assert tx.total_debits_cents == total
      assert tx.total_credits_cents == total

      lines =
        Repo.all(Ecto.Query.from(l in JournalLine, where: l.journal_transaction_id == ^tx.id))

      assert Enum.sum(Enum.map(lines, & &1.debit_cents)) == total
      assert Enum.sum(Enum.map(lines, & &1.credit_cents)) == total
    end
  end

  property "an unbalanced set of lines is always rejected and never partially persisted" do
    check all(
            debit_amount <- amount_generator(),
            credit_amount <- amount_generator(),
            debit_amount != credit_amount,
            debit_account <- account_generator(),
            credit_account <- account_generator(),
            max_runs: 50
          ) do
      reference = "prop-ledger-unbalanced-#{System.unique_integer([:positive])}"

      assert_raise ArgumentError, fn ->
        Journal.post!(
          reference,
          "KES",
          [{debit_account, :debit, debit_amount}, {credit_account, :credit, credit_amount}],
          %{}
        )
      end

      refute Repo.get_by(JournalTransaction, reference: reference)
    end
  end
end
