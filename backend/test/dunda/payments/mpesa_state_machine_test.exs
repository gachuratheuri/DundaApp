defmodule Dunda.Payments.MpesaStateMachineTest do
  use Dunda.DataCase, async: false

  @moduletag :redis

  alias Dunda.Payments.MpesaStateMachine
  alias Dunda.Inventory

  setup do
    # Clear only the keys these tests touch — never FLUSHDB a shared Redis.
    keys =
      ["inventory:tier:123", "escrow:tier:123", "user_escrow:1", "user_escrow:2"] ++
        Enum.flat_map(["tx_abc", "tx_def", "tx_ghi"], fn tx ->
          ["tx_user:#{tx}", "expiry:escrow:tier:123:#{tx}"]
        end) ++
        Enum.map(["idem_123", "idem_456", "idem_789"], &"checkout_request:ws_CO_SANDBOX_#{&1}")

    cleanup = fn -> Enum.each(keys, &Redix.command(:redix, ["DEL", &1])) end
    cleanup.()
    on_exit(cleanup)
    :ok
  end

  test "stk push success transitions idle to awaiting_callback" do
    attrs = %{
      transaction_id: "tx_abc",
      ticket_tier_id: "tier:123",
      user_id: 1,
      quantity: 1
    }

    {:ok, pid} = MpesaStateMachine.start_link(attrs)

    GenStateMachine.cast(pid, {:initiate, "0711223344", 100, "idem_123"})

    state = :sys.get_state(pid)
    assert elem(state, 0) == :awaiting_callback

    data = elem(state, 1)
    assert data.checkout_request_id != nil
  end

  test "callback received success settles, fulfils tickets, and stops the machine" do
    # Real fixtures: settlement enqueues the fulfillment worker inline (Oban
    # test mode), and a failing job would crash the machine mid-test.
    suffix = System.unique_integer([:positive])

    {:ok, user} =
      Dunda.Accounts.register_user(%{
        "email" => "machine-#{suffix}@example.com",
        "password" => "password123!",
        "name" => "Machine Test"
      })

    {:ok, event} =
      Repo.insert(
        Dunda.Events.Event.changeset(%Dunda.Events.Event{}, %{
          name: "Machine Test #{suffix}",
          venue: "Test Venue",
          starts_at: DateTime.utc_now() |> DateTime.add(7, :day) |> DateTime.truncate(:second),
          price_cents: 100_000,
          capacity: 10,
          status: "published",
          city: "Nairobi",
          currency: "KES"
        })
      )

    {:ok, tier} =
      Repo.insert(
        Dunda.Ticketing.TicketTier.changeset(%Dunda.Ticketing.TicketTier{}, %{
          event_id: event.id,
          name: "Regular",
          price_cents: 100_000,
          capacity: 10
        })
      )

    attrs = %{
      transaction_id: "tx_def",
      ticket_tier_id: "tier:#{tier.id}",
      user_id: user.id,
      quantity: 1
    }

    {:ok, pid} = MpesaStateMachine.start_link(attrs)
    GenStateMachine.cast(pid, {:initiate, "0711223344", 100, "idem_456"})

    GenStateMachine.cast(
      pid,
      {:callback_received, %{"ResultCode" => "0", "MpesaReceiptNumber" => "RXXXXXX"}}
    )

    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, _pid, :normal}, 5_000

    assert Dunda.Ledger.settled?("tx_def")
    assert Dunda.Ticketing.fulfilled?("tx_def")

    [ticket] = Dunda.Ticketing.list_user_tickets(user.id)
    assert ticket.tier_id == tier.id
    assert ticket.tier_label == "REGULAR"
  end

  test "callback received failure transitions awaiting_callback to release and stops process" do
    pool_id = "tier:123"
    tx_id = "tx_ghi"
    user_id = 2

    Redix.command!(:redix, ["SET", Inventory.inventory_key(pool_id), "10"])
    assert :ok = Inventory.acquire(pool_id, tx_id, 1, user_id)

    attrs = %{
      transaction_id: tx_id,
      ticket_tier_id: pool_id,
      user_id: user_id,
      quantity: 1
    }

    {:ok, pid} = MpesaStateMachine.start_link(attrs)
    GenStateMachine.cast(pid, {:initiate, "0711223344", 100, "idem_789"})

    GenStateMachine.cast(pid, {:callback_received, %{"ResultCode" => "1032"}})

    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, _pid, :normal}, 5_000

    assert Inventory.remaining(pool_id, 10) == 10
    assert nil == Redix.command!(:redix, ["GET", "user_escrow:#{user_id}"])
  end
end
