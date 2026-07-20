defmodule DundaWeb.MpesaController do
  use DundaWeb, :controller

  require Logger

  alias Dunda.Payments

  @doc """
  POST /api/mpesa/callback

  Safaricom posts the STK result here. We normalise the nested payload, extract
  the `MpesaReceiptNumber` from the callback metadata, and route it to the owning
  transaction by `CheckoutRequestID`. Always returns Daraja's expected 200 ack so
  Safaricom does not retry indefinitely.
  """
  def callback(conn, params) do
    unless Dunda.Security.Webhook.valid?(conn, :daraja) do
      conn
      |> put_status(:unauthorized)
      |> json(%{error: %{code: "invalid_webhook_signature"}})
      |> Plug.Conn.halt()
    else
    stk = get_in(params, ["Body", "stkCallback"]) || %{}
    checkout_request_id = stk["CheckoutRequestID"]

    normalised = %{
      "ResultCode" => to_string(stk["ResultCode"]),
      "MpesaReceiptNumber" => receipt_number(stk)
    }

    case checkout_request_id && Payments.deliver_callback(checkout_request_id, normalised) do
      :ok ->
        # QA FI-01: push live settlement telemetry to any subscribed client
        # socket so the app does not depend solely on HTTP status polling.
        DundaWeb.SettlementChannel.broadcast_settlement(checkout_request_id, normalised)
        :noop

      other ->
        Logger.warning("[Mpesa] Unroutable callback (#{inspect(other)}): #{inspect(stk)}")
    end

    # Daraja expects this exact acknowledgement shape.
    json(conn, %{"ResultCode" => 0, "ResultDesc" => "Accepted"})
    end
  end

  defp receipt_number(%{"CallbackMetadata" => %{"Item" => items}}) when is_list(items) do
    Enum.find_value(items, fn
      %{"Name" => "MpesaReceiptNumber", "Value" => value} -> value
      _ -> nil
    end)
  end

  defp receipt_number(_), do: nil
end
