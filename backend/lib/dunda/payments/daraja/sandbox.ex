defmodule Dunda.Payments.Daraja.Sandbox do
  @moduledoc """
  Deterministic in-memory Daraja adapter for local development and tests.

  It never performs network I/O. `stk_push/3` always succeeds and returns a
  synthetic `CheckoutRequestID`; `query_status/1` reports a settled result so
  the happy-path state-machine flow can be exercised end to end.
  """
  @behaviour Dunda.Payments.Daraja

  @impl true
  def stk_push(_phone, _amount, idempotency_key) do
    {:ok, "ws_CO_SANDBOX_" <> idempotency_key}
  end

  @impl true
  def query_status(_checkout_request_id) do
    {:ok,
     %{
       "ResultCode" => "0",
       "ResultDesc" => "The service request is processed successfully.",
       "MpesaReceiptNumber" => "SANDBOX" <> Integer.to_string(System.unique_integer([:positive]))
     }}
  end

  @impl true
  def b2c(_phone, _amount, _remarks) do
    {:ok, "AG_SANDBOX_" <> Integer.to_string(System.unique_integer([:positive]))}
  end
end
