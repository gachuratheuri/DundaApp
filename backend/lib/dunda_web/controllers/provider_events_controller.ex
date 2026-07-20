defmodule DundaWeb.ProviderEventsController do
  use DundaWeb, :controller
  alias Dunda.Checkout.ProviderEvent

  def create(conn, %{"provider" => provider} = params) do
    if Dunda.Containment.blocked?(:mpesa_callbacks) or Dunda.Containment.blocked?(:billing) do
      DundaWeb.ContainmentController.disabled(conn, params)
    else
      provider_atom = if provider == "mpesa", do: :daraja, else: :pesapal
      cond do
        not Dunda.Security.Webhook.valid?(conn, provider_atom) ->
          conn |> put_status(:unauthorized) |> json(%{error: %{code: "invalid_webhook_signature"}})
        true ->
          receive_event(conn, provider, params)
      end
    end
  end

  defp receive_event(conn, provider, params) do
    if Dunda.Containment.blocked?(:mpesa_callbacks) or Dunda.Containment.blocked?(:billing) do
      DundaWeb.ContainmentController.disabled(conn, params)
    else
      event_id = params["event_id"] || params["OrderNotificationId"] || params["CheckoutRequestID"] || "sha256:" <> Base.url_encode64(:crypto.hash(:sha256, Jason.encode!(params)), padding: false)
      checkout_id = params["provider_checkout_id"] || params["OrderTrackingId"] || params["CheckoutRequestID"]
      attrs = %{provider: provider, provider_event_id: to_string(event_id), provider_checkout_id: checkout_id, payload: params, received_at: DateTime.utc_now() |> DateTime.truncate(:second)}
      case Dunda.Checkout.record_provider_event(attrs) do
        {:ok, %ProviderEvent{} = event} ->
          case Dunda.Workers.ProviderEventWorker.new(%{"provider_event_id" => event.id}) |> Oban.insert() do
            {:ok, _job} -> conn |> put_status(:accepted) |> json(%{data: %{provider_event_id: event.id, status: "durably_received"}})
            {:error, reason} -> conn |> put_status(:service_unavailable) |> json(%{error: %{code: "provider_event_queued_failed", details: inspect(reason)}})
          end
        {:error, changeset} -> conn |> put_status(:unprocessable_entity) |> json(%{error: %{code: "provider_event_invalid", details: inspect(changeset.errors)}})
      end
    end
  end
end
