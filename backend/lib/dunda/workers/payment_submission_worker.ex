defmodule Dunda.Workers.PaymentSubmissionWorker do
  @moduledoc "Executes a provider request only after the local submission intent commits."
  use Oban.Worker, queue: :payments, max_attempts: 5
  alias Dunda.Checkout
  alias Dunda.Billing.Pesapal
  alias Dunda.Payments.Daraja

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"payment_intent_id" => intent_id}}) do
    if Dunda.Containment.blocked?(:checkout) do
      {:cancel, :phase_0_containment}
    else
      case Checkout.prepare_provider_submission(intent_id) do
        {:ok, {:already_submitted, _intent}} -> :ok
        {:ok, {:submit, intent, attempt}} -> submit(intent, attempt)
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp submit(intent, attempt) do
    case Application.get_env(:dunda, :checkout_provider, :pesapal) do
      :mpesa ->
        if rem(intent.amount_cents, 100) != 0 do
          normalise(
            Checkout.complete_provider_submission(intent.id, attempt.id, %{
              result: :failed,
              reason: :mpesa_requires_whole_kes_amount
            })
          )
        else
          submit_mpesa(intent, attempt)
        end

      _ ->
        submit_pesapal(intent, attempt)
    end
  end

  defp submit_mpesa(intent, attempt) do
    case Daraja.stk_push(
           intent.phone_encrypted,
           div(intent.amount_cents, 100),
           intent.idempotency_key
         ) do
      {:ok, checkout_id} ->
        normalise(
          Checkout.complete_provider_submission(intent.id, attempt.id, %{
            result: :ok,
            provider_checkout_id: checkout_id
          })
        )

      {:error, :pending} ->
        normalise(
          Checkout.complete_provider_submission(intent.id, attempt.id, %{
            result: :ambiguous,
            reason: :provider_pending
          })
        )

      {:error, reason} ->
        normalise(
          Checkout.complete_provider_submission(intent.id, attempt.id, %{
            result: :failed,
            reason: reason
          })
        )
    end
  end

  defp submit_pesapal(intent, attempt) do
    case Pesapal.submit_order(%{
           merchant_reference: "intent_#{intent.id}",
           amount_cents: intent.amount_cents,
           currency: intent.currency,
           phone: intent.phone_encrypted,
           description: "Dunda checkout"
         }) do
      {:ok, checkout_id} ->
        normalise(
          Checkout.complete_provider_submission(intent.id, attempt.id, %{
            result: :ok,
            provider_checkout_id: checkout_id.order_tracking_id,
            redirect_url: checkout_id.redirect_url
          })
        )

      {:error, reason} ->
        normalise(
          Checkout.complete_provider_submission(intent.id, attempt.id, %{
            result: :ambiguous,
            reason: reason
          })
        )
    end
  end

  defp normalise({:ok, _result}), do: :ok
  defp normalise({:error, reason}), do: {:error, reason}
end
