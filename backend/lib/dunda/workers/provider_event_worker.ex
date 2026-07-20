defmodule Dunda.Workers.ProviderEventWorker do
  @moduledoc "Deduplicated provider-event consumer; provider truth is checked before confirmation."
  use Oban.Worker, queue: :payments, max_attempts: 10
  import Ecto.Query, only: [from: 2]
  alias Dunda.Checkout.ProviderEvent
  alias Dunda.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"provider_event_id" => id}}) do
    if Dunda.Containment.blocked?(:mpesa_callbacks) or Dunda.Containment.blocked?(:billing) do
      {:cancel, :phase_0_containment}
    else
      event = Repo.get!(ProviderEvent, id)
      result = reconcile(event)
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      Repo.update!(Ecto.Changeset.change(event, %{outcome: inspect(result), processed_at: now}))
      :ok
    end
  end

  defp reconcile(%ProviderEvent{provider: "pesapal", provider_checkout_id: checkout_id}) when is_binary(checkout_id) do
    with {:ok, intent_id} <- intent_id(checkout_id) do
      case Dunda.Billing.Pesapal.transaction_status(checkout_id) do
        {:ok, %{"status_code" => code} = status} when code in [1, "1"] -> Dunda.Checkout.confirm_payment(intent_id, %{provider: "pesapal", provider_checkout_id: checkout_id, provider_receipt: receipt(status), amount_cents: amount(status), phone: status["phone"], merchant_reference: status["merchant_reference"]})
        {:ok, _} -> :provider_not_final
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, reason} -> {:manual_review, reason}
    end
  end
  defp reconcile(%ProviderEvent{provider: "mpesa", provider_checkout_id: checkout_id, payload: payload}) do
    with {:ok, intent_id} <- intent_id(checkout_id) do
      code = payload["ResultCode"] || payload["result_code"]
      if to_string(code) == "0", do: Dunda.Checkout.confirm_payment(intent_id, %{provider: "mpesa", provider_checkout_id: checkout_id, provider_receipt: payload["MpesaReceiptNumber"] || payload["receipt"], amount_cents: provider_amount(payload), phone: payload["PhoneNumber"] || payload["phone"], merchant_reference: payload["AccountReference"] || payload["account_reference"]}), else: Dunda.Checkout.fail_payment(intent_id, "provider_result_#{code}")
    else
      {:error, reason} -> {:manual_review, reason}
    end
  end
  defp reconcile(_), do: :unsupported_provider_event

  defp intent_id(checkout_id) when is_binary(checkout_id) do
    case Repo.one(from p in Dunda.Checkout.PaymentIntent, where: p.provider_checkout_id == ^checkout_id, select: p.id) do
      nil -> {:error, :payment_intent_correlation_missing}
      id -> {:ok, id}
    end
  end
  defp intent_id(_), do: {:error, :provider_checkout_id_missing}
  defp receipt(status), do: status["confirmation_code"] || status["receipt"] || "pesapal:#{status["status_code"]}"
  defp amount(status), do: provider_amount(status)
  defp provider_amount(%{"amount_cents" => value}), do: parse_cents(value)
  defp provider_amount(%{"amount" => value}), do: parse_shillings(value)
  defp provider_amount(%{"Amount" => value}), do: parse_shillings(value)
  defp provider_amount(_), do: 0
  defp parse_cents(v) when is_integer(v), do: v
  defp parse_cents(v) when is_binary(v), do: case Integer.parse(v) do {n, ""} -> n; _ -> 0 end
  defp parse_cents(_), do: 0
  defp parse_shillings(v) when is_integer(v), do: v * 100
  defp parse_shillings(v) when is_float(v), do: round(v * 100)
  defp parse_shillings(v) when is_binary(v) do
    case Float.parse(v) do {n, ""} -> round(n * 100); _ -> 0 end
  end
  defp parse_shillings(_), do: 0
end
