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
      Repo.all(from p in PaymentIntent, where: p.state == "provider_pending" and p.inserted_at < ^threshold, limit: 500)
      |> Enum.each(fn intent -> _ = Dunda.Checkout.advance_state(intent, "expired_pending_reconciliation", %{reason: "provider_pending_timeout"}) end)
      :ok
    end
  end
end
