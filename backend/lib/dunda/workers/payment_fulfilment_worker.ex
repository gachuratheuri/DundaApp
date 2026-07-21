defmodule Dunda.Workers.PaymentFulfilmentWorker do
  @moduledoc "Exactly-once settlement/fulfilment worker for confirmed intents."
  use Oban.Worker, queue: :payments, max_attempts: 10
  alias Dunda.Checkout
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"payment_intent_id" => id}}) do
    if Dunda.Containment.blocked?(:checkout) do
      {:cancel, :phase_0_containment}
    else
      case Checkout.fulfil_payment_intent(id) do
        {:error, reason}
        when reason in [:inventory_unavailable_for_fulfilment, :reservation_not_found] ->
          case Checkout.request_refund(id, "fulfilment_unavailable:#{inspect(reason)}") do
            {:ok, _intent} -> :ok
            {:error, refund_reason} -> {:error, {:refund_intent_failed, refund_reason}}
          end

        result ->
          result
      end
    end
  end
end
