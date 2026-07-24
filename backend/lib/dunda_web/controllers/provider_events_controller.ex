defmodule DundaWeb.ProviderEventsController do
  use DundaWeb, :controller
  alias Dunda.Checkout.ProviderEvent

  def create(conn, %{"provider" => provider} = params) when provider in ["mpesa", "pesapal"] do
    received_at_us = System.monotonic_time(:microsecond)

    if Dunda.Containment.blocked?(:mpesa_callbacks) or Dunda.Containment.blocked?(:billing) do
      DundaWeb.ContainmentController.disabled(conn, params)
    else
      provider_atom = if provider == "mpesa", do: :daraja, else: :pesapal

      cond do
        not Dunda.Security.Webhook.valid?(conn, provider_atom) ->
          conn
          |> put_status(:unauthorized)
          |> json(%{error: %{code: "invalid_webhook_signature"}})

        true ->
          receive_event(conn, provider, params, received_at_us)
      end
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: %{code: "unsupported_provider"}})
  end

  defp receive_event(conn, provider, params, received_at_us) do
    if Dunda.Containment.blocked?(:mpesa_callbacks) or Dunda.Containment.blocked?(:billing) do
      DundaWeb.ContainmentController.disabled(conn, params)
    else
      callback = get_in(params, ["Body", "stkCallback"]) || params["stkCallback"] || %{}

      checkout_id =
        params["provider_checkout_id"] || params["OrderTrackingId"] || params["CheckoutRequestID"] ||
          callback["CheckoutRequestID"]

      event_id =
        params["event_id"] || params["OrderNotificationId"] || checkout_id ||
          "sha256:" <>
            Base.url_encode64(:crypto.hash(:sha256, Jason.encode!(params)), padding: false)

      attrs = %{
        provider: provider,
        provider_event_id: to_string(event_id),
        provider_checkout_id: checkout_id,
        payload: params,
        received_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }

      case Dunda.Checkout.record_provider_event_and_enqueue(attrs) do
        {:ok, %ProviderEvent{} = event} ->
          # Durable-intent-committed-then-ack (Invariant 9): the ack timer
          # stops here, at the point the provider event is durably
          # persisted, not when the HTTP response is flushed — that's the
          # SLO's "webhook durable acknowledgement" instant.
          ack_ms = (System.monotonic_time(:microsecond) - received_at_us) / 1_000
          Dunda.Observability.gauge(:webhook_ack_ms_last, ack_ms)
          if ack_ms > 2_000, do: Dunda.Observability.increment(:webhook_ack_breach_total)

          conn
          |> put_status(:accepted)
          |> json(%{data: %{provider_event_id: event.id, status: "durably_received"}})

        {:error, %Ecto.Changeset{}} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: %{code: "provider_event_invalid"}})

        {:error, _reason} ->
          conn
          |> put_status(:service_unavailable)
          |> json(%{error: %{code: "provider_event_queue_unavailable"}})
      end
    end
  end
end
