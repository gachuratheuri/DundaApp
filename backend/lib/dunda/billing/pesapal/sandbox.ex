defmodule Dunda.Billing.Pesapal.Sandbox do
  @moduledoc """
  Deterministic, network-free Pesapal adapter for dev and tests. Mirrors the
  shape of the real API responses so the full submit → IPN → verify → confirm
  flow can be exercised end to end offline.
  """
  @behaviour Dunda.Billing.Pesapal

  @impl true
  def request_token, do: {:ok, "sandbox-token"}

  @impl true
  def register_ipn(_url), do: {:ok, "sandbox-ipn-" <> rand()}

  @impl true
  def list_ipns, do: {:ok, [%{"ipn_id" => "sandbox-ipn", "url" => "https://example.test/ipn"}]}

  @impl true
  def submit_order(order) do
    otid = "sandbox-otid-" <> Map.fetch!(order, :merchant_reference)

    {:ok,
     %{
       order_tracking_id: otid,
       redirect_url: "https://sandbox.pesapal.test/checkout/#{otid}"
     }}
  end

  @impl true
  def transaction_status(order_tracking_id) do
    {:ok,
     %{
       "order_tracking_id" => order_tracking_id,
       "payment_status_description" => "Completed",
       "status_code" => 1,
       "payment_method" => "MpesaSandbox",
       "amount" => 0.0
     }}
  end

  defp rand, do: Integer.to_string(System.unique_integer([:positive]))
end
