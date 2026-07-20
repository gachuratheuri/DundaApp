defmodule Dunda.Payments.MpesaStateMachine do
  @moduledoc """
  Per-transaction M-Pesa payment state machine.

  States: `:idle` → `:awaiting_callback` → (`:settled` | `:failed`)

  Reliability model: the Daraja callback is the fast path, but callbacks are
  best-effort, so a dead-letter poll is scheduled on entry to
  `:awaiting_callback`. Whichever resolves first wins; settlement is idempotent
  on the M-Pesa receipt (see `Dunda.Ledger.settle/3`).
  """
  use GenStateMachine, callback_mode: :state_functions

  require Logger

  alias Dunda.Inventory
  alias Dunda.Ledger
  alias Dunda.Payments.Daraja

  @callback_grace_ms 60_000
  @poll_backoff_ms 30_000

  @doc "Start a transaction state machine. `init_arg` must contain `:transaction_id`, `:ticket_tier_id`, `:user_id`."
  def start_link(init_arg, opts \\ []) do
    GenStateMachine.start_link(__MODULE__, init_arg, opts)
  end

  @doc """
  Start state requires the `transaction_id` plus the `ticket_tier_id`, `quantity`, and
  `user_id` whose escrow must be released on failure.
  """
  def init(%{transaction_id: _, ticket_tier_id: _, user_id: _, quantity: _} = attrs) do
    data =
      Map.merge(
        %{checkout_request_id: nil, retry_count: 0, max_poll_retries: 3},
        attrs
      )

    {:ok, :idle, data}
  end

  # Transition: idle → awaiting_callback
  def idle(:cast, {:initiate, phone, amount, idempotency_key}, data) do
    if Dunda.Containment.blocked?(:checkout) do
      {:stop, :normal, data}
    else
      case Daraja.stk_push(phone, amount, idempotency_key) do
      {:ok, checkout_request_id} ->
        new_data = %{data | checkout_request_id: checkout_request_id}
        # Index this process by CheckoutRequestID so the Daraja callback (which
        # only carries the CheckoutRequestID, not our transaction_id) can route.
        Dunda.Payments.register_checkout_id(checkout_request_id, new_data)
        # Schedule the dead-letter poll in case the callback never arrives.
        Process.send_after(self(), :poll_status, @callback_grace_ms)
        {:next_state, :awaiting_callback, new_data}

      {:error, reason} ->
        release(data)
        {:stop, :normal, Map.put(data, :failure_reason, reason)}
      end
    end
  end

  # Transition: awaiting_callback → settled (happy path callback)
  def awaiting_callback(
        :cast,
        {:callback_received, %{"ResultCode" => "0", "MpesaReceiptNumber" => receipt}},
        data
      ) do
    if Dunda.Containment.blocked?(:mpesa_callbacks) do
      {:stop, :normal, data}
    else
      case Ledger.settle(data.transaction_id, receipt) do
        {:ok, _entry} ->
          Dunda.Workers.MpesaFulfillmentWorker.enqueue(data.transaction_id, data.ticket_tier_id, data.user_id, data.quantity)
          Redix.command(:redix, ["DEL", "checkout_request:#{data.checkout_request_id}"])
          {:stop, :normal, Map.put(data, :receipt, receipt)}

        {:error, reason} ->
          Logger.error("M-Pesa settlement rejected for #{data.transaction_id}: #{inspect(reason)}")
          {:stop, :normal, Map.put(data, :failure_reason, reason)}
      end
    end
  end

  # Transition: awaiting_callback → failed (explicit failure callback)
  def awaiting_callback(:cast, {:callback_received, %{"ResultCode" => code}}, data)
      when code != "0" do
    if Dunda.Containment.blocked?(:mpesa_callbacks) do
      {:stop, :normal, data}
    else
      release(data)
      Redix.command(:redix, ["DEL", "checkout_request:#{data.checkout_request_id}"])
      {:stop, :normal, Map.put(data, :failure_code, code)}
    end
  end

  # Dead-letter poll trigger
  def awaiting_callback(:info, :poll_status, data) do
    if Dunda.Containment.blocked?(:checkout), do: {:stop, :normal, data}, else: handle_poll(data)
  end

  defp handle_poll(%{retry_count: count, max_poll_retries: max} = data) when count >= max do
    release(data)
    Redix.command(:redix, ["DEL", "checkout_request:#{data.checkout_request_id}"])
    {:stop, :normal, Map.put(data, :failure_reason, :poll_exhausted)}
  end

  defp handle_poll(data) do
    case Daraja.query_status(data.checkout_request_id) do
      {:ok, %{"ResultCode" => "0"} = result} ->
        case Ledger.settle(data.transaction_id, result["MpesaReceiptNumber"]) do
          {:ok, _entry} ->
            Dunda.Workers.MpesaFulfillmentWorker.enqueue(data.transaction_id, data.ticket_tier_id, data.user_id, data.quantity)
            Redix.command(:redix, ["DEL", "checkout_request:#{data.checkout_request_id}"])
            {:stop, :normal, data}

          {:error, reason} ->
            Logger.error("M-Pesa poll settlement rejected for #{data.transaction_id}: #{inspect(reason)}")
            {:stop, :normal, Map.put(data, :failure_reason, reason)}
        end

      {:ok, %{"ResultCode" => code}} when code != "0" ->
        release(data)
        Redix.command(:redix, ["DEL", "checkout_request:#{data.checkout_request_id}"])
        {:stop, :normal, Map.put(data, :failure_code, code)}

      {:error, :pending} ->
        Process.send_after(self(), :poll_status, @poll_backoff_ms)
        {:keep_state, Map.update!(data, :retry_count, &(&1 + 1))}
    end
  end

  defp release(%{ticket_tier_id: tier_id, transaction_id: transaction_id}) do
    Inventory.release_escrow(tier_id, transaction_id)
  end
end
