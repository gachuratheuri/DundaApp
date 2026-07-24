defmodule Dunda.Workers.FinancialReconciliationWorker do
  @moduledoc """
  Detects fulfilled intents without both their balanced settlement journal and
  beneficiary-specific payable. Provider-pending truth is reconciled by
  `PaymentReconciliationWorker`; this worker never races confirmed fulfilment.
  """
  use Oban.Worker, queue: :payments, max_attempts: 5
  import Ecto.Query, only: [from: 2]
  alias Dunda.Checkout.{JournalTransaction, PayableEntry, PaymentIntent}
  alias Dunda.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    if Dunda.Containment.blocked?(:checkout) do
      {:cancel, :phase_0_containment}
    else
      intents =
        Repo.all(
          from p in PaymentIntent,
            where: p.state == "fulfilled",
            limit: 1_000
        )

      diff_count =
        Enum.count(intents, fn intent ->
          journal = Repo.get_by(JournalTransaction, reference: "settlement:#{intent.id}")

          payable =
            Repo.get_by(PayableEntry,
              source_type: "payment_intent",
              source_id: intent.id
            )

          if is_nil(journal) or is_nil(payable) or payable.journal_transaction_id != journal.id do
            _ =
              Dunda.Checkout.advance_state(intent, "manual_review", %{
                reason: "settlement_or_beneficiary_payable_missing"
              })

            true
          else
            false
          end
        end)

      # "Zero unreconciled confirmed payments" is a root-plan SLO — this
      # gauge is its direct measurement.
      Dunda.Observability.gauge(:reconciliation_diff_count, diff_count)
      :ok
    end
  end
end
