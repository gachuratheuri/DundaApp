defmodule Dunda.Workers.PaymentRefundWorker do
  @moduledoc "Durable refund-intent handoff; provider-specific refund completion is reconciled separately."
  use Oban.Worker, queue: :payments, max_attempts: 10
  alias Dunda.Checkout
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"payment_intent_id" => id}}) do
    if Dunda.Containment.blocked?(:checkout) do
      {:cancel, :phase_0_containment}
    else
      # There is intentionally no fabricated provider success. The payment
      # remains refund_pending until a provider adapter/callback proves it.
      case Checkout.get_payment_intent(id) do
        nil -> {:error, :payment_intent_not_found}
        %{state: "refund_pending"} -> {:error, :refund_provider_adapter_required}
        _ -> :ok
      end
    end
  end
end
