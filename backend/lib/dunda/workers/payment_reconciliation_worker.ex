defmodule Dunda.Workers.PaymentReconciliationWorker do
  @moduledoc "Preserves provider correlation while moving aged pending intents to reconciliation."
  use Oban.Worker, queue: :payments, max_attempts: 5
  import Ecto.Query, only: [from: 2]
  alias Dunda.Checkout.PaymentIntent
  alias Dunda.Repo

  @pending_age_seconds 600

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    if Dunda.Containment.blocked?(:checkout) do
      {:cancel, :phase_0_containment}
    else
      threshold = DateTime.add(DateTime.utc_now(), -@pending_age_seconds, :second)

      stale =
        Repo.all(
          from p in PaymentIntent,
            where: p.state == "provider_pending" and p.inserted_at < ^threshold,
            limit: 500
        )

      Enum.each(stale, fn intent ->
        _ =
          Dunda.Checkout.advance_state(intent, "expired_pending_reconciliation", %{
            reason: "provider_pending_timeout"
          })
      end)

      # Business-invariant metrics (Phase 12 observability): current count
      # of payments that just crossed the pending-age threshold this run
      # (gauge — point-in-time), and a monotonic total moved to
      # reconciliation over the process lifetime.
      Dunda.Observability.gauge(:payment_pending_reconciliation_count, length(stale))

      if stale != [],
        do: Dunda.Observability.increment(:payment_reconciliation_moved_total, length(stale))

      :ok
    end
  end
end
