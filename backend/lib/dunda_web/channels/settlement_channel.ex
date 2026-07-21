defmodule DundaWeb.SettlementChannel do
  @moduledoc """
  Per-checkout settlement telemetry channel (QA FI-01).

  Topic: `settlement:<internal_payment_intent_id>`.

  On join the channel replies with the current ledger state so a client that
  connects late (or reconnects after a network blip) immediately re-syncs
  without waiting for the next broadcast. Settlement events are pushed by
  `DundaWeb.SettlementChannel.broadcast_settlement/2` from the M-Pesa callback
  path.
  """
  use Phoenix.Channel

  @impl true
  def join("settlement:" <> payment_intent_id, _payload, socket) do
    case Dunda.Checkout.get_payment_intent_for_user(payment_intent_id, socket.assigns.user_id) do
      nil ->
        {:error, %{reason: "not_found"}}

      intent ->
        {:ok, %{status: public_status(intent.state)},
         assign(socket, :payment_intent_id, intent.id)}
    end
  end

  @doc """
  Broadcasts a settlement update for a transaction to all subscribed clients.

  `result` is the normalised M-Pesa callback map, e.g.
  `%{"ResultCode" => "0", "MpesaReceiptNumber" => "ABC123"}`.
  """
  @spec broadcast_settlement(String.t(), map()) :: :ok
  def broadcast_settlement(reference, result) when is_binary(reference) do
    case resolve_intent(reference) do
      nil ->
        :ok

      intent ->
        DundaWeb.Endpoint.broadcast("settlement:#{intent.id}", "settled", %{
          status: if(to_string(result["ResultCode"]) == "0", do: "success", else: "failure"),
          receipt: result["MpesaReceiptNumber"]
        })
    end
  end

  defp resolve_intent(reference) do
    case Ecto.UUID.cast(reference) do
      {:ok, id} -> Dunda.Repo.get(Dunda.Checkout.PaymentIntent, id)
      :error -> Dunda.Repo.get_by(Dunda.Checkout.PaymentIntent, provider_checkout_id: reference)
    end
  end

  defp public_status(state) when state in ["confirmed", "confirmed_late", "fulfilled"],
    do: "success"

  defp public_status(state) when state in ["failed", "refunded"], do: "failure"
  defp public_status(_), do: "pending"
end
