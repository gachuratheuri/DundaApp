defmodule DundaWeb.IpnController do
  @moduledoc """
  Pesapal Instant Payment Notification (IPN) endpoint.

  Pesapal calls this URL (registered via `Dunda.Billing.Setup.setup_ipn/0`) when
  a transaction changes state. The notification is NOT trusted: we only extract
  the `OrderTrackingId`, enqueue `IpnVerificationWorker` to re-check the status
  out-of-band, and immediately acknowledge in the exact shape Pesapal expects.
  """
  use DundaWeb, :controller

  require Logger

  alias Dunda.Workers.IpnVerificationWorker

  # Pesapal may call via GET (default) or POST depending on registration type.
  def ipn(conn, params) do
    unless Dunda.Security.Webhook.valid?(conn, :pesapal) do
      conn
      |> put_status(:unauthorized)
      |> json(%{error: %{code: "invalid_webhook_signature"}})
      |> Plug.Conn.halt()
    else
      otid = params["OrderTrackingId"] || params["orderTrackingId"]
      ref = params["OrderMerchantReference"] || params["orderMerchantReference"]
      type = params["OrderNotificationType"] || params["orderNotificationType"]
      Logger.metadata(order_tracking_id: otid, merchant_reference: ref)

      status =
        case otid do
          nil ->
            Logger.warning(
              "IPN received without OrderTrackingId: #{inspect(Dunda.Logging.Redactor.redact(params))}"
            )

            500

          _ ->
            IpnVerificationWorker.enqueue(otid)
            200
        end

      json(conn, %{
        orderNotificationType: type,
        orderTrackingId: otid,
        orderMerchantReference: ref,
        status: status
      })
    end
  end
end
