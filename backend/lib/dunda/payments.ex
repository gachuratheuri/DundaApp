defmodule Dunda.Payments do
  @moduledoc """
  Orchestrates the purchase flow: reserve inventory, then drive an M-Pesa STK
  push through a supervised `MpesaStateMachine`.
  """
  alias Dunda.Inventory
  alias Dunda.Payments.MpesaStateMachine

  @supervisor Dunda.Payments.TransactionSupervisor
  @registry Dunda.Payments.TransactionRegistry

  @doc """
  Reserve `quantity` tickets for `user_id` on `tier_id` and initiate payment for
  `amount` KSh from `phone`. Returns `{:ok, transaction_id}` once the STK push
  has been kicked off, or `{:error, reason}` if inventory is unavailable.
  """
  @spec checkout(map()) :: {:ok, String.t()} | {:error, atom()}
  def checkout(%{tier_id: tier_id, user_id: user_id, quantity: quantity, phone: phone, amount: amount} = attrs) do
    if Dunda.Containment.blocked?(:checkout) do
      {:error, :phase_0_containment}
    else
      with {:ok, idempotency_key} <- validate_idempotency_key(Map.get(attrs, :idempotency_key)),
           {:ok, transaction_id, fresh?} <- reserve_idempotency(idempotency_key, attrs) do
        if not fresh? do
          {:ok, transaction_id}
        else
          case Inventory.acquire(tier_id, transaction_id, quantity, user_id) do
            {:error, reason} ->
              delete_idempotency(attrs.user_id, idempotency_key)
              {:error, reason}

            :ok ->
              start_transaction(attrs, idempotency_key, transaction_id, phone, amount)
          end
        end
      else
        {:error, _} = error -> error
      end
    end
  end

  defp start_transaction(attrs, idempotency_key, transaction_id, phone, amount) do
    case Horde.DynamicSupervisor.start_child(
               @supervisor,
               %{
                 id: MpesaStateMachine,
                 start:
                   {MpesaStateMachine, :start_link,
                    [
                      %{transaction_id: transaction_id, ticket_tier_id: attrs.tier_id, user_id: attrs.user_id, quantity: attrs.quantity},
                      [name: via(transaction_id)]
                    ]},
                 restart: :transient
               }
             ) do
          {:ok, pid} ->
            GenStateMachine.cast(pid, {:initiate, phone, amount, transaction_id})
            {:ok, transaction_id}

          {:error, reason} ->
            # Do not leave a replay key pointing at a transaction that never
            # acquired inventory or started a state machine.
            delete_idempotency(attrs.user_id, idempotency_key)
            Inventory.release_escrow(attrs.tier_id, transaction_id)
            {:error, reason}
        end
  end

  defp validate_idempotency_key(nil), do: {:ok, "internal-" <> Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)}
  defp validate_idempotency_key(key) when is_binary(key) and byte_size(key) in 16..200, do: {:ok, key}
  defp validate_idempotency_key(_), do: {:error, :idempotency_key_required}

  defp reserve_idempotency(key, attrs) do
    redis_key = "checkout:idempotency:v1:#{attrs.user_id}:#{key}"
    tx_id = generate_transaction_id()
    payload = Jason.encode!(%{transaction_id: tx_id, tier_id: attrs.tier_id, quantity: attrs.quantity, amount: attrs.amount, phone: attrs.phone})

    case Redix.command(:redix, ["SET", redis_key, payload, "EX", "86400", "NX"]) do
      {:ok, "OK"} -> {:ok, tx_id, true}
      {:ok, nil} ->
        case Redix.command(:redix, ["GET", redis_key]) do
          {:ok, existing} when is_binary(existing) ->
            case Jason.decode(existing) do
              {:ok, %{"transaction_id" => existing_tx, "tier_id" => tier, "quantity" => quantity, "amount" => amount, "phone" => phone}}
                  when tier == attrs.tier_id and quantity == attrs.quantity and amount == attrs.amount and phone == attrs.phone ->
                {:ok, existing_tx, false}
              _ -> {:error, :idempotency_conflict}
            end

          _ -> {:error, :idempotency_unavailable}
        end

      {:error, _} -> {:error, :idempotency_unavailable}
    end
  end

  defp delete_idempotency(user_id, key), do: Redix.command(:redix, ["DEL", "checkout:idempotency:v1:#{user_id}:#{key}"])

  @doc """
  Register the calling state-machine process under its `CheckoutRequestID` so a
  Daraja callback can be routed to it. Must be called from within the machine.
  """
  @spec register_checkout_id(String.t(), map()) :: :ok
  def register_checkout_id(checkout_request_id, metadata) do
    Horde.Registry.register(@registry, {:cri, checkout_request_id}, nil)

    tx_payload = %{
      "transaction_id" => metadata.transaction_id,
      "ticket_tier_id" => metadata.ticket_tier_id,
      "user_id" => metadata.user_id,
      "quantity" => metadata.quantity,
      "created_at" => System.system_time(:second)
    }

    # TTL of 10 minutes (600s)
    Redix.command(:redix, ["SET", "checkout_request:#{checkout_request_id}", Jason.encode!(tx_payload), "EX", "600"])
    :ok
  end

  @doc "Route a Daraja STK callback to the owning machine by `CheckoutRequestID`."
  @spec deliver_callback(String.t(), map()) :: :ok | {:error, :unknown_transaction}
  def deliver_callback(checkout_request_id, stk_callback) do
    if Dunda.Containment.blocked?(:mpesa_callbacks) do
      {:error, :phase_0_containment}
    else
      case Horde.Registry.lookup(@registry, {:cri, checkout_request_id}) do
      [{pid, _}] ->
        GenStateMachine.cast(pid, {:callback_received, stk_callback})
        :ok

      [] ->
        # Fallback: process is dead. Retrieve from Redis and process offline.
        case Redix.command(:redix, ["GET", "checkout_request:#{checkout_request_id}"]) do
          {:ok, nil} ->
            {:error, :unknown_transaction}

          {:ok, json} ->
            case Jason.decode(json) do
              {:ok, tx} ->
                process_callback_offline(tx, stk_callback)
                Redix.command(:redix, ["DEL", "checkout_request:#{checkout_request_id}"])
                :ok

              _ ->
                {:error, :malformed_state}
            end

          _ ->
            {:error, :redis_unavailable}
        end
      end
    end
  end

  defp process_callback_offline(tx, %{"ResultCode" => "0", "MpesaReceiptNumber" => receipt}) do
    case Dunda.Ledger.settle(tx["transaction_id"], receipt) do
      {:ok, _entry} ->
        Dunda.Workers.MpesaFulfillmentWorker.enqueue(
          tx["transaction_id"],
          tx["ticket_tier_id"],
          tx["user_id"],
          tx["quantity"]
        )

      {:error, _reason} ->
        :ok
    end
  end

  defp process_callback_offline(tx, _failed_callback) do
    Inventory.release_escrow(tx["ticket_tier_id"], tx["transaction_id"])
  end

  def child_specs do
    [
      {Horde.Registry, [name: @registry, keys: :unique, members: :auto]},
      {Horde.DynamicSupervisor, [name: @supervisor, strategy: :one_for_one, members: :auto]}
    ]
  end

  defp via(transaction_id), do: {:via, Horde.Registry, {@registry, transaction_id}}

  defp generate_transaction_id do
    "txn_" <> (:crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false))
  end
end
