defmodule Dunda.Workers.IpnVerificationWorker do
  @moduledoc """
  Verifies a Pesapal order out-of-band after an IPN (queue `payments`).

  The IPN endpoint never trusts the notification payload directly — it only
  carries the `order_tracking_id`. This worker calls `Billing.confirm_order/1`,
  which re-fetches the authoritative status from Pesapal's `GetTransactionStatus`
  before mutating the order. Idempotent across retries.
  """
  use Oban.Worker, queue: :payments, max_attempts: 8

  alias Dunda.Billing

  @spec enqueue(String.t()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue(order_tracking_id) do
    %{"order_tracking_id" => order_tracking_id} |> new() |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"order_tracking_id" => otid}}) do
    if Dunda.Containment.blocked?(:billing) do
      {:cancel, :phase_0_containment}
    else
      case Billing.confirm_order(otid) do
        {:ok, _order} -> :ok
        {:error, :order_not_found} -> {:cancel, :order_not_found}
        {:error, reason} -> {:error, reason}
      end
    end
  end
end
