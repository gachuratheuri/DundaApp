defmodule Dunda.Workers.PaymentRefundWorker do
  @moduledoc "Durable, idempotent refund submission and terminal reconciliation."
  use Oban.Worker, queue: :payments, max_attempts: 10
  alias Dunda.Checkout
  alias Dunda.Checkout.RefundProvider

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"payment_intent_id" => id},
        attempt: attempt,
        max_attempts: max_attempts
      }) do
    if Dunda.Containment.blocked?(:checkout) do
      {:cancel, :phase_0_containment}
    else
      case Checkout.get_payment_intent(id) do
        nil -> {:error, :payment_intent_not_found}
        %{state: "refunded"} -> :ok
        %{state: "refund_pending"} = intent -> submit(intent, attempt, max_attempts)
        _ -> :ok
      end
    end
  end

  defp submit(intent, attempt, max_attempts) do
    idempotency_key = "payment-intent:#{intent.id}:refund"

    case RefundProvider.submit(intent, idempotency_key) do
      {:ok, %{status: :succeeded, provider_reference: reference}} ->
        normalise(Checkout.complete_refund(intent.id, %{provider_reference: reference}))

      {:ok, %{status: :pending}} ->
        {:snooze, min(60 * attempt, 15 * 60)}

      {:manual_review, reason} ->
        normalise(Checkout.advance_state(intent, "manual_review", %{reason: to_string(reason)}))

      {:error, reason} when attempt >= max_attempts ->
        normalise(
          Checkout.advance_state(intent, "manual_review", %{
            reason: "refund_provider_exhausted:#{inspect(reason, limit: 10)}"
          })
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp normalise({:ok, _}), do: :ok
  defp normalise({:error, reason}), do: {:error, reason}
end
