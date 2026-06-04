defmodule Dunda.Inventory do
  @moduledoc """
  Public-facing facade over the per-tier `InventoryPoolServer` processes.

  Callers (HTTP controllers, the M-Pesa state machine, background workers)
  should depend on this module rather than reaching into the GenServer
  directly, keeping the process topology an implementation detail.
  """

  alias Dunda.Ticketing.InventoryPoolServer

  @type tier_id :: String.t() | integer()
  @type user_id :: String.t() | integer()

  @doc """
  Atomically reserve `quantity` tickets from `ticket_tier_id` into escrow for
  `user_id`. Returns `:ok` or `{:error, reason}`.
  """
  @spec acquire(tier_id(), user_id(), pos_integer()) ::
          :ok | {:error, atom()}
  def acquire(ticket_tier_id, user_id, quantity)
      when is_integer(quantity) and quantity > 0 do
    InventoryPoolServer.acquire_tickets(ticket_tier_id, user_id, quantity)
  end

  @doc """
  Release a user's escrowed tickets back into the available pool. Idempotent:
  releasing a non-existent escrow is a no-op.
  """
  @spec release_escrow(tier_id(), user_id()) :: :ok
  def release_escrow(ticket_tier_id, user_id) do
    InventoryPoolServer.release_escrow(ticket_tier_id, user_id)
  end
end
