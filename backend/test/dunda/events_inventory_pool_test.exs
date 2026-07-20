defmodule Dunda.EventsInventoryPoolTest do
  @moduledoc """
  Regression test for finding F0
  (`docs/phase_12_verification_observability_rollout.md`): before this fix,
  no application code path ever created a `Dunda.Checkout.InventoryPool`
  row for an event, so a real reservation against a normally-created event
  failed with `{:error, :inventory_pool_not_found}`. This test drives the
  full real path — `Dunda.Events.create_event/1` (not a test fixture that
  manually inserts a pool, which is what every other test in this session
  had to do to work around the bug) followed by
  `Dunda.Checkout.create_payment_intent/2` — end to end.
  """
  use Dunda.DataCase, async: false

  # Dunda.Events.create_event/1 also seeds a Redis projection
  # (seed_inventory/1) as part of the same transaction — this test needs a
  # reachable Redis, matching the convention test_helper.exs already
  # applies to every other test exercising create_event/1
  # (checkout_controller_test.exs, mpesa_settlement_test.exs).
  @moduletag :redis

  alias Dunda.Checkout
  alias Dunda.Checkout.InventoryPool
  alias Dunda.Events

  setup do
    Application.put_env(:dunda, :containment_mode, false)
    on_exit(fn -> Application.put_env(:dunda, :containment_mode, false) end)
    :ok
  end

  defp unique, do: System.unique_integer([:positive])

  defp insert_user! do
    n = unique()

    {:ok, user} =
      Dunda.Accounts.register_user(%{
        "email" => "f0-regression-#{n}@example.com",
        "password" => "password123!",
        "name" => "F0 Regression Test"
      })

    user
  end

  test "Dunda.Events.create_event/1 provisions a working untiered inventory pool" do
    n = unique()

    {:ok, event} =
      Events.create_event(%{
        name: "F0 Regression Event #{n}",
        venue: "Test Venue",
        starts_at: DateTime.utc_now() |> DateTime.add(7, :day) |> DateTime.truncate(:second),
        price_cents: 100_000,
        capacity: 25,
        status: "published",
        city: "Nairobi",
        currency: "KES"
      })

    pool = Repo.get_by(InventoryPool, event_id: event.id, ticket_tier_id: nil)
    assert pool
    assert pool.pool_key == "event:#{event.id}"
    assert pool.capacity == 25
    assert pool.reserved == 0
    assert pool.sold == 0
  end

  test "a real reservation succeeds end-to-end against a normally-created event (the actual F0 regression)" do
    user = insert_user!()
    n = unique()

    {:ok, event} =
      Events.create_event(%{
        name: "F0 Regression Checkout #{n}",
        venue: "Test Venue",
        starts_at: DateTime.utc_now() |> DateTime.add(7, :day) |> DateTime.truncate(:second),
        price_cents: 100_000,
        capacity: 10,
        status: "published",
        city: "Nairobi",
        currency: "KES"
      })

    {:ok, quote} = Checkout.create_quote(user.id, %{event_id: event.id, quantity: 1})

    assert {:ok, intent} =
             Checkout.create_payment_intent(user.id, %{
               quote_id: quote.id,
               idempotency_key: Base.encode16(:crypto.strong_rand_bytes(10)),
               phone: "254712345678"
             })

    assert intent.state == "inventory_reserved"

    pool = Repo.get_by(InventoryPool, event_id: event.id, ticket_tier_id: nil)
    assert pool.reserved == 1
  end

  describe "update_event/2 keeps the pool capacity in sync" do
    test "increasing capacity updates the pool" do
      n = unique()

      {:ok, event} =
        Events.create_event(%{
          name: "F0 Capacity Sync #{n}",
          venue: "Test Venue",
          starts_at: DateTime.utc_now() |> DateTime.add(7, :day) |> DateTime.truncate(:second),
          price_cents: 100_000,
          capacity: 10,
          status: "published",
          city: "Nairobi",
          currency: "KES"
        })

      assert {:ok, updated} = Events.update_event(event, %{capacity: 50})
      assert updated.capacity == 50

      pool = Repo.get_by(InventoryPool, event_id: event.id, ticket_tier_id: nil)
      assert pool.capacity == 50
    end

    test "reducing capacity below committed inventory is rejected, not silently dropped or crashed" do
      user = insert_user!()
      n = unique()

      {:ok, event} =
        Events.create_event(%{
          name: "F0 Capacity Reject #{n}",
          venue: "Test Venue",
          starts_at: DateTime.utc_now() |> DateTime.add(7, :day) |> DateTime.truncate(:second),
          price_cents: 100_000,
          capacity: 10,
          status: "published",
          city: "Nairobi",
          currency: "KES"
        })

      {:ok, quote} = Checkout.create_quote(user.id, %{event_id: event.id, quantity: 5})

      {:ok, _intent} =
        Checkout.create_payment_intent(user.id, %{
          quote_id: quote.id,
          idempotency_key: Base.encode16(:crypto.strong_rand_bytes(10)),
          phone: "254712345678"
        })

      assert {:error, :capacity_below_committed_inventory} = Events.update_event(event, %{capacity: 2})

      # Rejected update must not have partially applied — event row unchanged.
      # Reads via Repo (primary), not Events.get_event/1 (ReadRepo) — the
      # DataCase sandbox only checks out Dunda.Repo; ReadRepo would need its
      # own :auto-mode setup (see checkout_controller_test.exs) to be usable
      # in a transactional test like this one.
      reloaded = Repo.get(Dunda.Events.Event, event.id)
      assert reloaded.capacity == 10

      pool = Repo.get_by(InventoryPool, event_id: event.id, ticket_tier_id: nil)
      assert pool.capacity == 10
      assert pool.reserved == 5
    end
  end
end
