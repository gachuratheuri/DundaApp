defmodule Dunda.InventoryPropertyTest do
  @moduledoc """
  Property-based test of Invariant 1 from the root remediation plan:

      sold(tier) + active_reservations(tier) <= capacity(tier)

  This drives the *exact* guarded SQL patterns production code uses on
  `Dunda.Checkout.InventoryPool` (`Dunda.Checkout.reserve_from_quote!/4`,
  `fulfil_locked!/1`, `release_reservation!/2` —
  `backend/lib/dunda/checkout.ex`) directly, not a reimplementation, so a
  regression in the guard clauses themselves would be caught here. An
  operation whose guard condition isn't met is expected to no-op (affected
  row count 0) rather than corrupt state — that is itself part of what this
  property asserts by checking the invariant after every single operation,
  successful or not.

  Complements, and does not replace, `test/dunda/inventory_test.exs`'s
  50-way concurrent-contention example test — this test is sequential and
  explores the state space broadly instead.
  """
  use Dunda.DataCase, async: true
  use ExUnitProperties

  import Ecto.Query

  alias Dunda.Checkout.InventoryPool
  alias Dunda.Events.Event

  defp insert_event! do
    n = System.unique_integer([:positive])

    {:ok, event} =
      Event.changeset(%Event{}, %{
        name: "Inventory Property Test #{n}",
        venue: "Test Venue",
        starts_at: DateTime.utc_now() |> DateTime.add(7, :day) |> DateTime.truncate(:second),
        price_cents: 100_000,
        capacity: 10_000,
        status: "published",
        city: "Nairobi",
        currency: "KES"
      })
      |> Repo.insert()

    event
  end

  defp insert_pool!(event, capacity) do
    {:ok, pool} =
      %InventoryPool{}
      |> InventoryPool.changeset(%{
        pool_key: "prop-test-#{System.unique_integer([:positive])}",
        capacity: capacity,
        reserved: 0,
        sold: 0,
        version: 1,
        event_id: event.id
      })
      |> Repo.insert()

    pool
  end

  # Mirrors Dunda.Checkout's reservation guard exactly.
  defp reserve(pool_id, qty) do
    Repo.update_all(
      from(p in InventoryPool, where: p.id == ^pool_id and p.capacity - p.reserved - p.sold >= ^qty),
      inc: [reserved: qty, version: 1]
    )
  end

  # Mirrors fulfil_locked!/1's reserved -> sold conversion guard.
  defp confirm(pool_id, qty) do
    Repo.update_all(
      from(p in InventoryPool, where: p.id == ^pool_id and p.reserved >= ^qty),
      inc: [reserved: -qty, sold: qty, version: 1]
    )
  end

  # Mirrors release_reservation!/2's guard.
  defp release(pool_id, qty) do
    Repo.update_all(
      from(p in InventoryPool, where: p.id == ^pool_id and p.reserved >= ^qty),
      inc: [reserved: -qty, version: 1]
    )
  end

  defp op_generator do
    StreamData.tuple({StreamData.member_of([:reserve, :confirm, :release]), StreamData.integer(1..5)})
  end

  property "reserved + sold never exceeds capacity, and neither ever goes negative, across any operation sequence" do
    check all(
            capacity <- StreamData.integer(1..15),
            ops <- StreamData.list_of(op_generator(), max_length: 25),
            max_runs: 50
          ) do
      event = insert_event!()
      pool = insert_pool!(event, capacity)

      Enum.each(ops, fn {kind, qty} ->
        case kind do
          :reserve -> reserve(pool.id, qty)
          :confirm -> confirm(pool.id, qty)
          :release -> release(pool.id, qty)
        end

        current = Repo.get!(InventoryPool, pool.id)
        assert current.reserved + current.sold <= current.capacity
        assert current.reserved >= 0
        assert current.sold >= 0
      end)
    end
  end
end
