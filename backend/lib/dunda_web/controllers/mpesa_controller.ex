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
    stk = get_in(params, ["Body", "stkCallback"]) || %{}
    checkout_request_id = stk["CheckoutRequestID"]

    normalised = %{
      "ResultCode" => to_string(stk["ResultCode"]),
      "MpesaReceiptNumber" => receipt_number(stk)
    }

    case checkout_request_id && Payments.deliver_callback(checkout_request_id, normalised) do
      :ok ->
        :noop

      other ->
        Logger.warning("[Mpesa] Unroutable callback (#{inspect(other)}): #{inspect(stk)}")
    end

    # Daraja expects this exact acknowledgement shape.
    json(conn, %{"ResultCode" => 0, "ResultDesc" => "Accepted"})
  end

  defp receipt_number(%{"CallbackMetadata" => %{"Item" => items}}) when is_list(items) do
    Enum.find_value(items, fn
      %{"Name" => "MpesaReceiptNumber", "Value" => value} -> value
      _ -> nil
    end)
  end

  defp receipt_number(_), do: nil
end
