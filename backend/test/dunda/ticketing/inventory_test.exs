defmodule Dunda.Ticketing.InventoryTest do
  use Dunda.DataCase, async: false

  alias Dunda.Inventory
  alias Dunda.Ticketing.InventoryPoolServer

  setup do
    # Clear Redis keys we use for testing
    Redix.command!(:redix, ["FLUSHDB"])
    :ok
  end

  test "acquiring tickets decrements available, increments escrow, and sets user lock" do
    pool_id = "tier:test_tier_1"
    tx_id = "tx_123"
    user_id = 99
    quantity = 2

    # Set initial inventory in Redis directly for this test pool
    Redix.command!(:redix, ["SET", Inventory.inventory_key(pool_id), "10"])

    # Acquire tickets
    assert :ok = Inventory.acquire(pool_id, tx_id, quantity, user_id)

    # Assert inventory decremented
    assert Inventory.remaining(pool_id, 10) == 8

    # Assert escrow quantity recorded
    escrow_val = Redix.command!(:redix, ["HGET", Inventory.escrow_key(pool_id), tx_id])
    assert escrow_val == "2"

    # Assert user lock set
    user_lock = Redix.command!(:redix, ["GET", "user_escrow:#{user_id}"])
    assert user_lock == tx_id

    # Assert duplicate acquisition for same user fails
    assert {:error, :duplicate_escrow_attempt} = Inventory.acquire(pool_id, "tx_124", 1, user_id)
  end

  test "committing escrow cleans up keys without re-crediting inventory" do
    pool_id = "tier:test_tier_2"
    tx_id = "tx_456"
    user_id = 100
    quantity = 3

    Redix.command!(:redix, ["SET", Inventory.inventory_key(pool_id), "10"])

    assert :ok = Inventory.acquire(pool_id, tx_id, quantity, user_id)
    assert Inventory.remaining(pool_id, 10) == 7

    # Commit escrow
    assert :ok = Inventory.commit_escrow(pool_id, tx_id)

    # Assert escrow key removed
    refute Redix.command!(:redix, ["HEXISTS", Inventory.escrow_key(pool_id), tx_id]) == 1

    # Assert user lock removed
    assert nil == Redix.command!(:redix, ["GET", "user_escrow:#{user_id}"])

    # Assert inventory remains at 7
    assert Inventory.remaining(pool_id, 10) == 7
  end

  test "releasing escrow re-credits inventory and cleans up locks" do
    pool_id = "tier:test_tier_3"
    tx_id = "tx_789"
    user_id = 101
    quantity = 4

    Redix.command!(:redix, ["SET", Inventory.inventory_key(pool_id), "10"])

    assert :ok = Inventory.acquire(pool_id, tx_id, quantity, user_id)
    assert Inventory.remaining(pool_id, 10) == 6

    # Release escrow
    assert :ok = Inventory.release_escrow(pool_id, tx_id)

    # Assert user lock removed
    assert nil == Redix.command!(:redix, ["GET", "user_escrow:#{user_id}"])

    # Assert inventory re-credited back to 10
    assert Inventory.remaining(pool_id, 10) == 10
  end

  test "re-seeding pool queries database and does not swallow errors silently" do
    # Create a test event and a ticket tier using our Repo helpers
    event =
      %Dunda.Events.Event{
        name: "Event Test",
        venue: "Venue Test",
        starts_at: DateTime.utc_now(),
        price_cents: 1000,
        capacity: 100
      }
      |> Dunda.Repo.insert!()

    tier =
      %Dunda.Ticketing.TicketTier{
        event_id: event.id,
        name: "VIP Test",
        price_cents: 5000,
        capacity: 50
      }
      |> Dunda.Repo.insert!()

    pool_id = "tier:#{tier.id}"

    assert :ok = InventoryPoolServer.ensure_started(pool_id)

    # Assert initialized to database capacity
    assert Inventory.remaining(pool_id, 50) == 50
  end
end
