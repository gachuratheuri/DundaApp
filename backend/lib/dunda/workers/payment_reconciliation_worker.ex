defmodule Dunda.Workers.PaymentReconciliationWorker do
  @moduledoc """
  Actively reconciles provider-pending intents. Callback delivery is an
  acceleration only: an omitted callback cannot strand a captured payment.
  """

  use Oban.Worker,
    queue: :payments,
    max_attempts: 20,
    unique: [period: 240, fields: [:args], keys: [:payment_intent_id]]

  import Ecto.Query, only: [from: 2]
  alias Dunda.Checkout.PaymentIntent
  alias Dunda.Repo

  @pending_age_seconds 600
  @batch_size 100

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"payment_intent_id" => id}}) do
    if Dunda.Containment.blocked?(:checkout) do
      {:cancel, :phase_0_containment}
    else
      case Repo.get(PaymentIntent, id) do
        nil -> :ok
        intent -> reconcile(intent)
      end
    end
  end

  def perform(%Oban.Job{}) do
    if Dunda.Containment.blocked?(:checkout) do
      {:cancel, :phase_0_containment}
    else
      threshold = DateTime.add(DateTime.utc_now(), -@pending_age_seconds, :second)

      stale =
        Repo.all(
          from p in PaymentIntent,
            where:
              p.state in ["provider_pending", "expired_pending_reconciliation"] and
                p.inserted_at < ^threshold and not is_nil(p.provider_checkout_id),
            order_by: [asc: p.inserted_at],
            limit: @batch_size
        )

      Enum.each(stale, &reconcile/1)

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

  defp reconcile(%PaymentIntent{state: state})
       when state not in ["provider_pending", "expired_pending_reconciliation"],
       do: :ok

  defp reconcile(%PaymentIntent{provider: "pesapal"} = intent) do
    case Dunda.Billing.Pesapal.transaction_status(intent.provider_checkout_id) do
      {:ok, %{"status_code" => code} = status} when code in [1, "1"] ->
        confirm_or_review(intent, %{
          provider: "pesapal",
          provider_checkout_id: intent.provider_checkout_id,
          provider_receipt: status["confirmation_code"] || status["receipt"],
          amount_cents: provider_amount(status),
          phone: status["phone"],
          merchant_reference: status["merchant_reference"]
        })

      {:ok, %{"status_code" => code}} when code in [2, "2", 3, "3"] ->
        Dunda.Checkout.fail_payment(intent.id, "provider_result_#{code}")

      {:ok, _status} ->
        mark_unresolved(intent, "pesapal_status_not_final")

      {:error, reason} ->
        mark_unresolved(intent, "pesapal_query_failed:#{bounded(reason)}")
    end
  end

  defp reconcile(%PaymentIntent{provider: "mpesa"} = intent) do
    case Dunda.Payments.Daraja.query_status(intent.provider_checkout_id) do
      {:ok, status} ->
        code = status["ResultCode"] || status["result_code"]

        cond do
          is_nil(code) ->
            mark_unresolved(intent, "mpesa_status_not_final")

          to_string(code) == "0" ->
            confirm_or_review(intent, %{
              provider: "mpesa",
              provider_checkout_id: intent.provider_checkout_id,
              provider_receipt: status["MpesaReceiptNumber"] || status["receipt"],
              amount_cents: provider_amount(status),
              phone: status["PhoneNumber"] || status["phone"],
              merchant_reference: status["AccountReference"] || status["account_reference"]
            })

          true ->
            Dunda.Checkout.fail_payment(intent.id, "provider_result_#{code}")
        end

      {:error, :pending} ->
        mark_unresolved(intent, "mpesa_status_pending")

      {:error, reason} ->
        mark_unresolved(intent, "mpesa_query_failed:#{bounded(reason)}")
    end
  end

  defp reconcile(%PaymentIntent{} = intent),
    do: move_to_manual_review(intent, "unsupported_checkout_provider")

  defp confirm_or_review(intent, attrs) do
    if is_binary(attrs.provider_receipt) and attrs.amount_cents > 0 do
      case Dunda.Checkout.confirm_payment(intent.id, attrs) do
        {:ok, _confirmed} = result ->
          result

        {:error, reason} ->
          move_to_manual_review(intent, "provider_confirmation_failed:#{bounded(reason)}")
      end
    else
      move_to_manual_review(intent, "provider_success_metadata_incomplete")
    end
  end

  defp mark_unresolved(%PaymentIntent{state: "provider_pending"} = intent, reason) do
    Dunda.Checkout.advance_state(intent, "expired_pending_reconciliation", %{reason: reason})
  end

  defp mark_unresolved(%PaymentIntent{}, _reason), do: :ok

  defp move_to_manual_review(%PaymentIntent{} = intent, reason) do
    current = Repo.get(PaymentIntent, intent.id)

    if current && current.state in ["provider_pending", "expired_pending_reconciliation"] do
      Dunda.Checkout.advance_state(current, "manual_review", %{reason: reason})
    else
      :ok
    end
  end

  defp provider_amount(%{"amount_cents" => value}), do: parse_cents(value)
  defp provider_amount(%{"amount" => value}), do: parse_shillings(value)
  defp provider_amount(%{"Amount" => value}), do: parse_shillings(value)
  defp provider_amount(_), do: 0
  defp parse_cents(value) when is_integer(value), do: value

  defp parse_cents(value) when is_binary(value) do
    case Integer.parse(value) do
      {amount, ""} -> amount
      _ -> 0
    end
  end

  defp parse_cents(_), do: 0
  defp parse_shillings(value) when is_integer(value), do: value * 100
  defp parse_shillings(value) when is_float(value), do: round(value * 100)

  defp parse_shillings(value) when is_binary(value) do
    case Float.parse(value) do
      {amount, ""} -> round(amount * 100)
      _ -> 0
    end
  end

  defp parse_shillings(_), do: 0

  defp bounded(reason),
    do: reason |> inspect(limit: 10, printable_limit: 200) |> String.slice(0, 300)
end
