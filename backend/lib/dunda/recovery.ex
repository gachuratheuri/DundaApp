defmodule Dunda.Recovery do
  @moduledoc "Operational recovery primitives; PostgreSQL remains the source of truth."
  import Ecto.Query, only: [from: 2]
  alias Dunda.Checkout.InventoryPool
  alias Dunda.Repo

  def rebuild_redis_projection, do: Dunda.Checkout.reconcile_redis_projection()

  def inventory_projection_report do
    Repo.all(from p in InventoryPool, select: {p.pool_key, p.capacity, p.reserved, p.sold})
    |> Enum.map(fn {pool_key, capacity, reserved, sold} ->
      expected = max(capacity - reserved - sold, 0)
      redis =
        case Redix.command(:redix, ["GET", Dunda.Inventory.inventory_key(pool_key)]) do
          {:ok, value} when is_binary(value) ->
            case Integer.parse(value) do
              {parsed, ""} -> parsed
              _ -> nil
            end

          _ ->
            nil
        end
      %{pool_key: pool_key, expected: expected, redis: redis, equal?: redis == expected}
    end)
  end

  def redis_projection_consistent? do
    Enum.all?(inventory_projection_report(), & &1.equal?)
  rescue
    _ -> false
  end
end
