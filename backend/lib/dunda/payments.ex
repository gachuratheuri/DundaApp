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
  def checkout(%{tier_id: tier_id, user_id: user_id, quantity: quantity, phone: phone, amount: amount}) do
    with :ok <- Inventory.acquire(tier_id, user_id, quantity) do
      transaction_id = generate_transaction_id()

      {:ok, pid} =
        Horde.DynamicSupervisor.start_child(
          @supervisor,
          %{
            id: MpesaStateMachine,
            start:
              {MpesaStateMachine, :start_link,
               [
                 %{transaction_id: transaction_id, ticket_tier_id: tier_id, user_id: user_id, quantity: quantity},
                 [name: via(transaction_id)]
               ]},
            restart: :transient
          }
        )

      GenStateMachine.cast(pid, {:initiate, phone, amount, transaction_id})
      {:ok, transaction_id}
    end
  end

  @doc """
  Register the calling state-machine process under its `CheckoutRequestID` so a
  Daraja callback can be routed to it. Must be called from within the machine.
  """
  @spec register_checkout_id(String.t()) :: :ok
  def register_checkout_id(checkout_request_id) do
    Horde.Registry.register(@registry, {:cri, checkout_request_id}, nil)
    :ok
  end

  @doc "Route a Daraja STK callback to the owning machine by `CheckoutRequestID`."
  @spec deliver_callback(String.t(), map()) :: :ok | {:error, :unknown_transaction}
  def deliver_callback(checkout_request_id, stk_callback) do
    case Horde.Registry.lookup(@registry, {:cri, checkout_request_id}) do
      [{pid, _}] ->
        GenStateMachine.cast(pid, {:callback_received, stk_callback})
        :ok

      [] ->
        {:error, :unknown_transaction}
    end
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
