defmodule DundaWeb.SettlementChannel do
  @moduledoc """
  Per-checkout settlement telemetry channel (QA FI-01).

  Topic: `settlement:<transaction_id>`.

  On join the channel replies with the current ledger state so a client that
  connects late (or reconnects after a network blip) immediately re-syncs
  without waiting for the next broadcast. Settlement events are pushed by
  `DundaWeb.SettlementChannel.broadcast_settlement/2` from the M-Pesa callback
  path.
  """
  use Phoenix.Channel

  @impl true
  def join("settlement:" <> transaction_id, _payload, socket) do
    status =
      if Dunda.Ledger.settled?(transaction_id), do: "success", else: "pending"

    {:ok, %{status: status}, assign(socket, :transaction_id, transaction_id)}
  end

  @doc """
  Broadcasts a settlement update for a transaction to all subscribed clients.

  `result` is the normalised M-Pesa callback map, e.g.
  `%{"ResultCode" => "0", "MpesaReceiptNumber" => "ABC123"}`.
  """
  @spec broadcast_settlement(String.t(), map()) :: :ok
  def broadcast_settlement(transaction_id, result) when is_binary(transaction_id) do
    status = if result["ResultCode"] == "0", do: "success", else: "failure"

    DundaWeb.Endpoint.broadcast("settlement:#{transaction_id}", "settled", %{
      status: status,
      receipt: result["MpesaReceiptNumber"]
    })
  end
end
