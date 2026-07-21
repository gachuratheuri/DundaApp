defmodule Dunda.InventoryTest do
  @moduledoc "Verifies that Redis inventory is a rebuildable PostgreSQL projection."

  use Dunda.DataCase, async: false

  @moduletag :redis

  alias Dunda.Checkout.InventoryPool
  alias Dunda.Events.Event

  test "reconciliation overwrites a stale Redis count from authoritative database state" do
    unique = System.unique_integer([:positive])

    event =
      %Event{}
      |> Event.changeset(%{
        name: "Projection Test #{unique}",
        venue: "Test Venue",
        starts_at: DateTime.utc_now() |> DateTime.add(7, :day) |> DateTime.truncate(:second),
        price_cents: 1_000,
        capacity: 10,
        status: "published",
        city: "Nairobi",
        currency: "KES"
      })
      |> Repo.insert!()

    pool =
      %InventoryPool{}
      |> InventoryPool.changeset(%{
        pool_key: "projection-test-#{unique}",
        event_id: event.id,
        capacity: 10,
        reserved: 3,
        sold: 4,
        version: 1
      })
      |> Repo.insert!()

    key = Dunda.Inventory.inventory_key(pool.pool_key)
    assert {:ok, "OK"} = Redix.command(:redix, ["SET", key, "999"])
    on_exit(fn -> Redix.command(:redix, ["DEL", key]) end)

    assert :ok = Dunda.Checkout.reconcile_redis_projection()
    assert {:ok, "3"} = Redix.command(:redix, ["GET", key])
  end
end
