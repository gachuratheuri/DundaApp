defmodule Dunda.Workers.MpesaPoller do
  @moduledoc """
  Scheduled sweeper worker that queries Safaricom status for active M-Pesa
  STK requests stored in Redis that did not receive a webhook callback.
  """
  use Oban.Worker, queue: :payments, max_attempts: 3
  require Logger

  alias Dunda.Payments.Daraja
  alias Dunda.Ledger
  alias Dunda.Inventory

  @poll_grace_seconds 90

  @impl Oban.Worker
  def perform(%Oban.Job{args: _}) do
    if Dunda.Containment.blocked?(:checkout) do
      {:cancel, :phase_0_containment}
    else
      keys = scan_keys("0", [])
      now = System.system_time(:second)

      Enum.each(keys, fn key ->
        case Redix.command(:redix, ["GET", key]) do
          {:ok, json} when is_binary(json) ->
            case Jason.decode(json) do
              {:ok, tx} ->
                created_at = Map.get(tx, "created_at", 0)

                if now - created_at >= @poll_grace_seconds do
                  "checkout_request:" <> checkout_request_id = key
                  poll_transaction(checkout_request_id, tx)
                end

              _ ->
                Redix.command(:redix, ["DEL", key])
            end

          _ ->
            :noop
        end
      end)

      :ok
    end
  end

  defp poll_transaction(checkout_request_id, tx) do
    Logger.info(
      "[MpesaPoller] Polling status for transaction #{tx["transaction_id"]} / CRI #{checkout_request_id}"
    )

    case Daraja.query_status(checkout_request_id) do
      {:ok, %{"ResultCode" => "0"} = result} ->
        receipt = result["MpesaReceiptNumber"]
        # Log a correlation-safe fingerprint, never the raw receipt number
        # (Phase 11 log-redaction hardening).
        receipt_fingerprint =
          :crypto.hash(:sha256, receipt || "")
          |> Base.encode16(case: :lower)
          |> String.slice(0, 12)

        Logger.info(
          "[MpesaPoller] Transaction #{tx["transaction_id"]} settled successfully via poller. Receipt fingerprint: #{receipt_fingerprint}"
        )

        Ledger.settle(tx["transaction_id"], receipt)

        Dunda.Workers.MpesaFulfillmentWorker.enqueue(
          tx["transaction_id"],
          tx["ticket_tier_id"],
          tx["user_id"],
          tx["quantity"]
        )

        Redix.command(:redix, ["DEL", "checkout_request:#{checkout_request_id}"])

      {:ok, %{"ResultCode" => code}} when code != "0" ->
        Logger.warning(
          "[MpesaPoller] Transaction #{tx["transaction_id"]} failed with Safaricom code: #{code}"
        )

        Inventory.release_escrow(tx["ticket_tier_id"], tx["transaction_id"])
        Redix.command(:redix, ["DEL", "checkout_request:#{checkout_request_id}"])

      {:error, :pending} ->
        # Still pending, leave it in Redis to check on next run
        :noop

      error ->
        Logger.error(
          "[MpesaPoller] Daraja API query failed for #{tx["transaction_id"]}: #{inspect(error)}"
        )

        :noop
    end
  end

  defp scan_keys(cursor, acc) do
    case Redix.command(:redix, ["SCAN", cursor, "MATCH", "checkout_request:*", "COUNT", "100"]) do
      {:ok, [next_cursor, keys]} ->
        new_acc = acc ++ keys

        if next_cursor == "0" do
          new_acc
        else
          scan_keys(next_cursor, new_acc)
        end

      _ ->
        acc
    end
  end
end
