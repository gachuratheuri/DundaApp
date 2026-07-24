defmodule Dunda.Inventory do
  @moduledoc """
  Public-facing facade over per-pool inventory state.

  A *pool id* names one unit of sellable inventory and is namespaced to avoid
  id collisions between entities:

    * `"tier:<ticket_tier_id>"` — the normal case; one pool per ticket tier.
    * `"event:<event_id>"` — legacy fallback for events with no tiers
      (e.g. scraped events).

  PostgreSQL is the sole authority. Redis remaining counts are rebuildable
  discovery projections.
  """
  import Ecto.Query, only: [from: 2]

  @type pool_id :: String.t()

  @doc "Returns the sole configured inventory authority."
  def authority, do: :postgres

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

  @doc """
  Projected remaining count for `pool_id`. If Redis is absent, malformed, or
  unreachable under PostgreSQL authority, read the authoritative pool row.
  """
  @spec remaining(pool_id(), integer() | nil) :: integer() | nil
  def remaining(pool_id, fallback \\ nil) do
    case Redix.command(:redix, ["GET", inventory_key(pool_id)]) do
      {:ok, nil} -> authoritative_remaining(pool_id, fallback)
      {:ok, value} -> parse_remaining(value, pool_id, fallback)
      _ -> authoritative_remaining(pool_id, fallback)
    end
  end

  defp parse_remaining(value, pool_id, fallback) do
    case Integer.parse(value) do
      {remaining, ""} when remaining >= 0 -> remaining
      _ -> authoritative_remaining(pool_id, fallback)
    end
  end

  defp authoritative_remaining(pool_id, fallback) do
    Dunda.Repo.one(
      from p in Dunda.Checkout.InventoryPool,
        where: p.pool_key == ^pool_id,
        select: p.capacity - p.reserved - p.sold
    ) || fallback
  rescue
    _ -> fallback
  end
end
