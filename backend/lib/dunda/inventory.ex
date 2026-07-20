defmodule Dunda.Inventory do
  @moduledoc """
  Public-facing facade over per-pool inventory state.

  A *pool id* names one unit of sellable inventory and is namespaced to avoid
  id collisions between entities:

    * `"tier:<ticket_tier_id>"` — the normal case; one pool per ticket tier.
    * `"event:<event_id>"` — legacy fallback for events with no tiers
      (e.g. scraped events).

  Acquisition is serialised through a per-pool `InventoryPoolServer` (which
  also seeds the Redis counter from Postgres on first use). Release and commit
  are single atomic Lua scripts executed directly against Redis: they need no
  serialisation point, and going through a GenServer would silently drop the
  operation when the pool process is not running — fatal for `commit_escrow/2`,
  where a drop means the reclaimer later re-credits already-sold tickets.
  """
  require Logger

  alias Dunda.Ticketing.InventoryPoolServer

  @type pool_id :: String.t()
  @type owner_id :: String.t() | integer()

  @doc "Returns the configured inventory authority. Production must use PostgreSQL."
  def authority, do: Application.get_env(:dunda, :inventory_authority, :postgres)

  @release_lua """
  local inv_key    = KEYS[1]
  local escrow_key = KEYS[2]
  local owner_id   = ARGV[1]
  local qty = redis.call("HGET", escrow_key, owner_id)
  if qty then
    redis.call("INCRBY", inv_key, tonumber(qty))
    redis.call("HDEL", escrow_key, owner_id)
    redis.call("DEL", "expiry:" .. escrow_key .. ":" .. owner_id)

    local tx_user_key = "tx_user:" .. owner_id
    local user_id = redis.call("GET", tx_user_key)
    if user_id then
      redis.call("DEL", "user_escrow:" .. user_id)
      redis.call("DEL", tx_user_key)
    end
  end
  return 1
  """

  @commit_lua """
  local escrow_key = KEYS[1]
  local owner_id   = ARGV[1]
  redis.call("HDEL", escrow_key, owner_id)
  redis.call("DEL", "expiry:" .. escrow_key .. ":" .. owner_id)

  local tx_user_key = "tx_user:" .. owner_id
  local user_id = redis.call("GET", tx_user_key)
  if user_id then
    redis.call("DEL", "user_escrow:" .. user_id)
    redis.call("DEL", tx_user_key)
  end
  return 1
  """

  @doc "Pool id for a ticket tier."
  @spec tier_pool(integer() | String.t()) :: pool_id()
  def tier_pool(tier_id), do: "tier:#{tier_id}"

  @doc "Pool id for a tierless (legacy) event."
  @spec event_pool(integer() | String.t()) :: pool_id()
  def event_pool(event_id), do: "event:#{event_id}"

  @doc "Redis key holding the live remaining count for `pool_id`."
  @spec inventory_key(pool_id()) :: String.t()
  # Hash tags keep the pool's inventory and escrow keys colocated if the
  # deployment later moves to Redis Cluster. Phase 1 still runs standalone
  # because the user-level lock keys are cross-pool by design.
  def inventory_key(pool_id), do: "inventory:{#{pool_id}}"

  @doc "Redis hash holding pending escrows for `pool_id`."
  @spec escrow_key(pool_id()) :: String.t()
  def escrow_key(pool_id), do: "escrow:{#{pool_id}}"

  @doc """
  Atomically reserve `quantity` tickets from `pool_id` into escrow for
  `owner_id` (the checkout's transaction id). Returns `:ok` or `{:error, reason}`.
  """
  @spec acquire(pool_id(), owner_id(), pos_integer(), String.t() | integer()) :: :ok | {:error, atom()}
  def acquire(pool_id, owner_id, quantity, user_id)
      when is_integer(quantity) and quantity > 0 do
    case authority() do
      :postgres -> {:error, :postgres_authority_required}
      :redis_legacy -> InventoryPoolServer.acquire_tickets(pool_id, owner_id, quantity, user_id)
    end
  end

  @doc """
  Release an escrow back into the available pool (failed or expired payment).
  Idempotent: releasing a non-existent escrow is a no-op. A Redis failure here
  is logged but tolerated — the escrow's expiry marker still lapses, so the
  `EscrowReclaimer` sweep performs the same release later.
  """
  @spec release_escrow(pool_id(), owner_id()) :: :ok | {:error, atom()}
  def release_escrow(pool_id, owner_id) do
    if authority() == :postgres, do: {:error, :postgres_authority_required}, else: release_escrow_legacy(pool_id, owner_id)
  end

  defp release_escrow_legacy(pool_id, owner_id) do
    case run_lua(@release_lua, [inventory_key(pool_id), escrow_key(pool_id)], [to_string(owner_id)]) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "[Inventory] release failed for #{pool_id} (reclaimer will recover): #{inspect(reason)}"
        )

        :ok
    end
  end

  @doc """
  Consume an escrow after settlement: the tickets are sold, so the escrow entry
  (and its expiry marker) are deleted *without* crediting the pool. Must be
  called on every successful settlement — otherwise the escrow reclaimer will
  eventually re-credit inventory that was actually sold. Idempotent. Errors are
  returned (not swallowed) so callers running under Oban retry the commit.
  """
  @spec commit_escrow(pool_id(), owner_id()) :: :ok | {:error, term()}
  def commit_escrow(pool_id, owner_id) do
    if authority() == :postgres, do: {:error, :postgres_authority_required}, else: run_lua(@commit_lua, [escrow_key(pool_id)], [to_string(owner_id)])
  end

  defp run_lua(script, keys, argv) do
    case Redix.command(:redix, ["EVAL", script, length(keys)] ++ keys ++ argv) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Live remaining count for `pool_id`, or `fallback` when the counter has not
  been seeded (or Redis is unreachable).
  """
  @spec remaining(pool_id(), integer() | nil) :: integer() | nil
  def remaining(pool_id, fallback \\ nil) do
    case Redix.command(:redix, ["GET", inventory_key(pool_id)]) do
      {:ok, nil} -> fallback
      {:ok, value} -> String.to_integer(value)
      _ -> fallback
    end
  end
end
