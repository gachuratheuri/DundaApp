defmodule Dunda.Workers.ProviderEventWorker do
  @moduledoc "Deduplicated provider-event consumer; provider truth is checked before confirmation."
  use Oban.Worker,
    queue: :payments,
    max_attempts: 10,
    unique: [period: :infinity, fields: [:args], keys: [:provider_event_id]]

  import Ecto.Query, only: [from: 2]
  alias Dunda.Checkout.ProviderEvent
  alias Dunda.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"provider_event_id" => id}, attempt: attempt}) do
    if Dunda.Containment.blocked?(:mpesa_callbacks) or Dunda.Containment.blocked?(:billing) do
      {:cancel, :phase_0_containment}
    else
      event = Repo.get!(ProviderEvent, id)

      if event.processed_at do
        :ok
      else
        event = increment_attempt!(event)

        case reconcile(event) do
          {:terminal, outcome} ->
            mark_terminal!(event, outcome)
            :ok

          {:retry, reason} ->
            mark_retryable!(event, reason)
            {:snooze, retry_delay(attempt)}
        end
      end
    end
  end

  defp reconcile(%ProviderEvent{provider: "pesapal", provider_checkout_id: checkout_id})
       when is_binary(checkout_id) do
    with {:ok, intent_id} <- intent_id(checkout_id) do
      case Dunda.Billing.Pesapal.transaction_status(checkout_id) do
        {:ok, %{"status_code" => code} = status} when code in [1, "1"] ->
          settlement_result(
            intent_id,
            Dunda.Checkout.confirm_payment(intent_id, %{
              provider: "pesapal",
              provider_checkout_id: checkout_id,
              provider_receipt: receipt(status),
              amount_cents: amount(status),
              phone: status["phone"],
              merchant_reference: status["merchant_reference"]
            })
          )

        {:ok, %{"status_code" => code}} when code in [2, "2", 3, "3"] ->
          settlement_result(
            intent_id,
            Dunda.Checkout.fail_payment(intent_id, "provider_result_#{code}")
          )

        {:ok, _} ->
          {:retry, :provider_not_final}

        {:error, reason} ->
          {:retry, {:provider_query_failed, reason}}
      end
    else
      {:error, reason} -> {:terminal, {:manual_review, reason}}
    end
  end

  defp reconcile(
         %ProviderEvent{
           provider: "mpesa",
           provider_checkout_id: checkout_id
         } = event
       ) do
    with {:ok, intent_id} <- intent_id(checkout_id) do
      # Daraja callbacks do not provide a provider-verifiable signature. The
      # callback is therefore only evidence carrying receipt metadata; the
      # authoritative STK query must independently confirm the correlated
      # CheckoutRequestID before any settlement transition is accepted.
      case Dunda.Payments.Daraja.query_status(checkout_id) do
        {:ok, status} ->
          reconcile_mpesa_status(
            intent_id,
            checkout_id,
            status,
            normalise_mpesa_callback(event_payload(event))
          )

        {:error, :pending} ->
          {:retry, :provider_not_final}

        {:error, reason} ->
          {:retry, {:provider_query_failed, reason}}
      end
    else
      {:error, reason} -> {:terminal, {:manual_review, reason}}
    end
  end

  defp reconcile(_), do: {:terminal, {:manual_review, :unsupported_provider_event}}

  defp reconcile_mpesa_status(intent_id, checkout_id, status, callback) do
    authoritative_checkout_id = status["CheckoutRequestID"] || status["checkout_request_id"]
    code = status["ResultCode"] || status["result_code"]

    cond do
      is_binary(authoritative_checkout_id) and authoritative_checkout_id != checkout_id ->
        manual_review(intent_id, :provider_checkout_mismatch)

      is_nil(code) ->
        {:retry, :provider_not_final}

      to_string(code) == "0" ->
        receipt = callback["MpesaReceiptNumber"] || callback["receipt"]
        amount_cents = provider_amount(callback)

        if is_binary(receipt) and amount_cents > 0 do
          settlement_result(
            intent_id,
            Dunda.Checkout.confirm_payment(intent_id, %{
              provider: "mpesa",
              provider_checkout_id: checkout_id,
              provider_receipt: receipt,
              amount_cents: amount_cents,
              phone: callback["PhoneNumber"] || callback["phone"],
              merchant_reference: callback["AccountReference"] || callback["account_reference"]
            })
          )
        else
          manual_review(intent_id, :provider_success_metadata_incomplete)
        end

      true ->
        settlement_result(
          intent_id,
          Dunda.Checkout.fail_payment(intent_id, "provider_result_#{code}")
        )
    end
  end

  defp manual_review(intent_id, reason) do
    case Dunda.Checkout.get_payment_intent(intent_id) do
      nil ->
        {:terminal, {:manual_review, reason}}

      intent ->
        terminal_result(
          Dunda.Checkout.advance_state(intent, "manual_review", %{reason: to_string(reason)})
        )
    end
  end

  defp terminal_result({:ok, value}), do: {:terminal, {:ok, value}}
  defp terminal_result({:error, reason}), do: {:terminal, {:manual_review, reason}}

  defp settlement_result(_intent_id, {:ok, value}), do: {:terminal, {:ok, value}}
  defp settlement_result(intent_id, {:error, reason}), do: manual_review(intent_id, reason)

  defp increment_attempt!(event) do
    event
    |> Ecto.Changeset.change(%{retry_count: event.retry_count + 1})
    |> Repo.update!()
  end

  defp mark_terminal!(event, outcome) do
    event
    |> Ecto.Changeset.change(%{
      outcome: bounded_outcome(outcome),
      processed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update!()
  end

  defp mark_retryable!(event, reason) do
    event
    |> Ecto.Changeset.change(%{outcome: bounded_outcome({:retry, reason}), processed_at: nil})
    |> Repo.update!()
  end

  defp bounded_outcome(outcome),
    do: outcome |> inspect(limit: 20, printable_limit: 500) |> String.slice(0, 1_000)

  defp retry_delay(attempt), do: min(15 * trunc(:math.pow(2, max(attempt - 1, 0))), 15 * 60)

  defp normalise_mpesa_callback(%{"Body" => %{"stkCallback" => callback}}),
    do: merge_callback_metadata(callback)

  defp normalise_mpesa_callback(%{"stkCallback" => callback}) when is_map(callback),
    do: merge_callback_metadata(callback)

  defp normalise_mpesa_callback(payload) when is_map(payload),
    do: merge_callback_metadata(payload)

  defp event_payload(%ProviderEvent{payload_encrypted: encrypted, payload: fallback})
       when is_binary(encrypted) do
    case Jason.decode(encrypted) do
      {:ok, payload} when is_map(payload) -> payload
      _ -> fallback
    end
  end

  defp event_payload(%ProviderEvent{payload: payload}), do: payload

  defp merge_callback_metadata(callback) do
    items = get_in(callback, ["CallbackMetadata", "Item"]) || []

    metadata =
      Enum.reduce(items, %{}, fn
        %{"Name" => name, "Value" => value}, acc -> Map.put(acc, name, value)
        _, acc -> acc
      end)

    Map.merge(callback, metadata)
  end

  defp intent_id(checkout_id) when is_binary(checkout_id) do
    case Repo.one(
           from p in Dunda.Checkout.PaymentIntent,
             where: p.provider_checkout_id == ^checkout_id,
             select: p.id
         ) do
      nil -> {:error, :payment_intent_correlation_missing}
      id -> {:ok, id}
    end
  end

  defp intent_id(_), do: {:error, :provider_checkout_id_missing}

  defp receipt(status),
    do: status["confirmation_code"] || status["receipt"]

  defp amount(status), do: provider_amount(status)
  defp provider_amount(%{"amount_cents" => value}), do: parse_cents(value)
  defp provider_amount(%{"amount" => value}), do: parse_shillings(value)
  defp provider_amount(%{"Amount" => value}), do: parse_shillings(value)
  defp provider_amount(_), do: 0
  defp parse_cents(v) when is_integer(v), do: v

  defp parse_cents(v) when is_binary(v) do
    case Integer.parse(v) do
      {n, ""} -> n
      _ -> 0
    end
  end

  defp parse_cents(_), do: 0
  defp parse_shillings(v) when is_integer(v), do: v * 100
  defp parse_shillings(v) when is_float(v), do: round(v * 100)

  defp parse_shillings(v) when is_binary(v) do
    case Float.parse(v) do
      {n, ""} -> round(n * 100)
      _ -> 0
    end
  end

  defp parse_shillings(_), do: 0
end
