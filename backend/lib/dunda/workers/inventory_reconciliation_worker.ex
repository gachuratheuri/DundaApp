defmodule Dunda.Workers.InventoryReconciliationWorker do
  @moduledoc "Rebuilds disposable Redis inventory projections from PostgreSQL authority."
  use Oban.Worker, queue: :inventory, max_attempts: 5
  alias Dunda.Checkout
  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    if Dunda.Containment.blocked?(:checkout) do
      {:cancel, :phase_0_containment}
    else
      case Checkout.reconcile_redis_projection() do
        :ok -> :ok
        {:error, _reason} = error -> Dunda.Observability.increment(:inventory_reconciliation_failed_total); error
      end
    end
  end
end
