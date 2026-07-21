defmodule Dunda.Workers.InventoryProjectionWorker do
  @moduledoc "Projects one authoritative inventory pool into disposable Redis state."

  use Oban.Worker,
    queue: :inventory,
    max_attempts: 20,
    unique: [period: 60, fields: [:args], keys: [:inventory_pool_id]]

  alias Dunda.Checkout.InventoryPool
  alias Dunda.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"inventory_pool_id" => pool_id}}) do
    case Repo.get(InventoryPool, pool_id) do
      nil ->
        :ok

      pool ->
        remaining = pool.capacity - pool.reserved - pool.sold

        case Redix.command(:redix, [
               "SET",
               Dunda.Inventory.inventory_key(pool.pool_key),
               Integer.to_string(remaining)
             ]) do
          {:ok, "OK"} -> :ok
          {:error, reason} -> {:error, {:redis_projection_failed, reason}}
          other -> {:error, {:unexpected_redis_projection_result, other}}
        end
    end
  end
end
