defmodule Dunda.InventoryTest do
  @moduledoc """
  Integration tests for the escrow inventory engine against a real Redis:
  the no-oversell guarantee under concurrency, the per-user duplicate-escrow
  lock, and the release / commit / reclaim lifecycle.

  Pool counters are seeded directly in Redis (bypassing the Postgres seed path)
  so these tests exercise the Lua semantics in isolation from the DB.
  """
  use ExUnit.Case, async: false

  @moduletag :redis

  alias Dunda.Inventory
  alias Dunda.Workers.EscrowReclaimer

  setup do
    pool_id = Inventory.tier_pool(System.unique_integer([:positive]))
    inv_key = Inventory.inventory_key(pool_id)
    escrow_key = Inventory.escrow_key(pool_id)

    on_exit(fn ->
      {:ok, keys} = Redix.command(:redix, ["KEYS", "*#{pool_id}*"])
      {:ok, user_keys} = Redix.command(:redix, ["KEYS", "user_escrow:#{pool_id}-*"])
      {:ok, tx_keys} = Redix.command(:redix, ["KEYS", "tx_user:#{pool_id}-*"])
      Enum.each(keys ++ user_keys ++ tx_keys, &Redix.command(:redix, ["DEL", &1]))
    end)

    {:ok, pool_id: pool_id, inv_key: inv_key, escrow_key: escrow_key}
  end

  # Owner (transaction) and user ids namespaced by pool so parallel runs and
  # leftover state can never collide.
  defp txn(pool_id, n), do: "#{pool_id}-txn-#{n}"
  defp user(pool_id, n), do: "#{pool_id}-user-#{n}"

  defp seed(inv_key, count) do
    {:ok, _} = Redix.command(:redix, ["SET", inv_key, to_string(count)])
  end

  defp int(key) do
    case Redix.command(:redix, ["GET", key]) do
      {:ok, nil} -> nil
      {:ok, value} -> String.to_integer(value)
    end
  end

  test "no oversell: concurrent acquires never exceed capacity", ctx do
    capacity = 10
    contenders = 50
    seed(ctx.inv_key, capacity)

    results =
      1..contenders
      |> Task.async_stream(
        fn n -> Inventory.acquire(ctx.pool_id, txn(ctx.pool_id, n), 1, user(ctx.pool_id, n)) end,
        max_concurrency: contenders,
        timeout: 10_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    successes = Enum.count(results, &(&1 == :ok))
    sold_out = Enum.count(results, &(&1 == {:error, :insufficient_inventory}))

    assert successes == capacity
    assert sold_out == contenders - capacity
    assert int(ctx.inv_key) == 0

    {:ok, escrow_entries} = Redix.command(:redix, ["HLEN", ctx.escrow_key])
    assert escrow_entries == capacity
  end

  test "per-user lock: one pending checkout per user", ctx do
    seed(ctx.inv_key, 10)
    buyer = user(ctx.pool_id, 1)

    assert :ok = Inventory.acquire(ctx.pool_id, txn(ctx.pool_id, 1), 2, buyer)

    assert {:error, :duplicate_escrow_attempt} =
             Inventory.acquire(ctx.pool_id, txn(ctx.pool_id, 2), 1, buyer)

    # A different user is unaffected.
    assert :ok = Inventory.acquire(ctx.pool_id, txn(ctx.pool_id, 3), 1, user(ctx.pool_id, 2))
  end

  test "release restores inventory and frees the user lock", ctx do
    seed(ctx.inv_key, 10)
    buyer = user(ctx.pool_id, 1)

    assert :ok = Inventory.acquire(ctx.pool_id, txn(ctx.pool_id, 1), 3, buyer)
    assert int(ctx.inv_key) == 7

    assert :ok = Inventory.release_escrow(ctx.pool_id, txn(ctx.pool_id, 1))
    assert int(ctx.inv_key) == 10

    {:ok, escrow_entries} = Redix.command(:redix, ["HLEN", ctx.escrow_key])
    assert escrow_entries == 0

    # The buyer can immediately check out again.
    assert :ok = Inventory.acquire(ctx.pool_id, txn(ctx.pool_id, 2), 1, buyer)

    # Releasing an unknown escrow is a no-op.
    assert :ok = Inventory.release_escrow(ctx.pool_id, txn(ctx.pool_id, 99))
    assert int(ctx.inv_key) == 9
  end

  test "commit consumes the escrow without re-crediting inventory", ctx do
    seed(ctx.inv_key, 10)
    buyer = user(ctx.pool_id, 1)
    transaction = txn(ctx.pool_id, 1)

    assert :ok = Inventory.acquire(ctx.pool_id, transaction, 4, buyer)
    assert int(ctx.inv_key) == 6

    assert :ok = Inventory.commit_escrow(ctx.pool_id, transaction)

    # Sold means sold: the counter stays down and the escrow entry is gone.
    assert int(ctx.inv_key) == 6
    {:ok, escrow_entries} = Redix.command(:redix, ["HLEN", ctx.escrow_key])
    assert escrow_entries == 0

    # The buyer's lock is freed for their next purchase.
    assert :ok = Inventory.acquire(ctx.pool_id, txn(ctx.pool_id, 2), 1, buyer)

    # Commit is idempotent.
    assert :ok = Inventory.commit_escrow(ctx.pool_id, transaction)
    assert int(ctx.inv_key) == 5
  end

  test "reclaimer releases lapsed escrows but never committed ones", ctx do
    seed(ctx.inv_key, 10)

    committed_txn = txn(ctx.pool_id, 1)
    lapsed_txn = txn(ctx.pool_id, 2)

    assert :ok = Inventory.acquire(ctx.pool_id, committed_txn, 2, user(ctx.pool_id, 1))
    assert :ok = Inventory.acquire(ctx.pool_id, lapsed_txn, 3, user(ctx.pool_id, 2))
    assert int(ctx.inv_key) == 5

    # The first payment settles; the second's expiry marker lapses unresolved.
    assert :ok = Inventory.commit_escrow(ctx.pool_id, committed_txn)
    {:ok, _} = Redix.command(:redix, ["DEL", "expiry:#{ctx.escrow_key}:#{lapsed_txn}"])

    assert :ok =
             EscrowReclaimer.perform(%Oban.Job{args: %{"ticket_tier_id" => ctx.pool_id}})

    # Only the lapsed escrow's 3 tickets return; the committed 2 stay sold.
    assert int(ctx.inv_key) == 8
    {:ok, escrow_entries} = Redix.command(:redix, ["HLEN", ctx.escrow_key])
    assert escrow_entries == 0
  end
end
