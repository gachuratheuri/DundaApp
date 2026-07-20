defmodule Dunda.Workers.InventoryReconciliationWorker do
  @moduledoc "Rebuilds disposable Redis inventory projections from PostgreSQL authority."
  use Oban.Worker, queue: :inventory, max_attempts: 5
  alias Dunda.Checkout
  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    if Dunda.Containment.blocked?(:checkout), do: {:cancel, :phase_0_containment}, else: Checkout.reconcile_redis_projection()
  end
end
