defmodule Dunda.Payments.MpesaSettlementTest do
  @moduledoc """
  End-to-end settlement tests: checkout → STK push (sandbox) → callback or
  dead-letter poll → ledger settle → inline fulfillment → escrow commit.

  These run against real Postgres *and* Redis with committed fixtures (sandbox
  in `:auto` mode): the state machine, the Oban-inline fulfillment worker, and
  the read-replica repo all live outside the test process, so transactional
  sandboxing cannot make fixtures visible to them.
  """
  use ExUnit.Case, async: false

  @moduletag :redis

  import Ecto.Query, only: [from: 2]

  alias Dunda.Accounts
  alias Dunda.Events
  alias Dunda.Inventory
  alias Dunda.Ledger
  alias Dunda.Payments
  alias Dunda.Ticketing

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Dunda.Repo, :auto)
    Ecto.Adapters.SQL.Sandbox.mode(Dunda.ReadRepo, :auto)

    suffix = System.unique_integer([:positive])

    {:ok, user} =
      Accounts.register_user(%{
        "email" => "settlement-#{suffix}@example.com",
        "password" => "password123!",
        "name" => "Settlement Test"
      })

    {:ok, event} =
      Events.create_event(%{
        name: "Settlement Test #{suffix}",
        venue: "Test Venue",
        starts_at: DateTime.utc_now() |> DateTime.add(30, :day) |> DateTime.truncate(:second),
        price_cents: 150_000,
        capacity: 100,
        status: "published",
        city: "Nairobi",
        currency: "KES"
      })

    pool_id = Inventory.event_pool(event.id)

    on_exit(fn ->
      Dunda.Repo.delete_all(from t in Ticketing.Ticket, where: t.event_id == ^event.id)

      Dunda.Repo.delete_all(from e in Dunda.Ledger.Entry, where: like(e.transaction_id, "txn_%"))

      Dunda.Repo.delete_all(from e in Events.Event, where: e.id == ^event.id)
      Dunda.Repo.delete_all(from u in Accounts.User, where: u.id == ^user.id)

      {:ok, keys} = Redix.command(:redix, ["KEYS", "*#{pool_id}*"])
      Enum.each(keys, &Redix.command(:redix, ["DEL", &1]))
      Redix.command(:redix, ["DEL", "user_escrow:#{user.id}"])

      Ecto.Adapters.SQL.Sandbox.mode(Dunda.Repo, :manual)
    end)

    {:ok, user: user, event: event, pool_id: pool_id}
  end

  defp checkout(ctx, quantity) do
    {:ok, transaction_id} =
      Payments.checkout(%{
        tier_id: ctx.pool_id,
        user_id: ctx.user.id,
        quantity: quantity,
        phone: "+254712345678",
        amount: div(150_000 * quantity, 100)
      })

    pid = await_machine(transaction_id)
    cri = "ws_CO_SANDBOX_" <> transaction_id

    await(fn ->
      Horde.Registry.lookup(Dunda.Payments.TransactionRegistry, {:cri, cri}) != []
    end)

    {transaction_id, cri, pid}
  end

  defp await_machine(transaction_id) do
    await(fn ->
      case Horde.Registry.lookup(Dunda.Payments.TransactionRegistry, transaction_id) do
        [{pid, _}] -> pid
        [] -> false
      end
    end)
  end

  defp await(fun, attempts \\ 50) do
    case fun.() do
      false when attempts > 0 ->
        Process.sleep(20)
        await(fun, attempts - 1)

      false ->
        flunk("condition never became true")

      result ->
        result
    end
  end

  defp inventory(ctx), do: Inventory.remaining(ctx.pool_id)

  test "successful callback settles, fulfils, and commits the escrow", ctx do
    {transaction_id, cri, pid} = checkout(ctx, 2)
    assert inventory(ctx) == 98

    ref = Process.monitor(pid)
    receipt = "SETTLE-CB-#{System.unique_integer([:positive])}"

    assert :ok =
             Payments.deliver_callback(cri, %{
               "ResultCode" => "0",
               "MpesaReceiptNumber" => receipt
             })

    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5_000

    assert Ledger.settled?(transaction_id)

    # Fulfillment ran inline: exactly-once tickets bound to this transaction.
    assert Ticketing.fulfilled?(transaction_id)
    tickets = Ticketing.list_user_tickets(ctx.user.id)
    assert length(tickets) == 2
    assert Enum.all?(tickets, &(&1.event_id == ctx.event.id and &1.status == "valid"))

    # The escrow was committed, not released: sold tickets stay sold.
    assert inventory(ctx) == 98
    assert {:ok, 0} = Redix.command(:redix, ["HLEN", Inventory.escrow_key(ctx.pool_id)])

    # The buyer's per-user checkout lock is freed.
    assert {:ok, 0} = Redix.command(:redix, ["EXISTS", "user_escrow:#{ctx.user.id}"])
  end

  test "failed callback releases the escrow and settles nothing", ctx do
    {transaction_id, cri, pid} = checkout(ctx, 3)
    assert inventory(ctx) == 97

    ref = Process.monitor(pid)

    assert :ok = Payments.deliver_callback(cri, %{"ResultCode" => "1032"})
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5_000

    refute Ledger.settled?(transaction_id)
    refute Ticketing.fulfilled?(transaction_id)
    assert Ticketing.list_user_tickets(ctx.user.id) == []

    # Inventory returned and the buyer's lock is freed.
    assert inventory(ctx) == 100
    assert {:ok, 0} = Redix.command(:redix, ["EXISTS", "user_escrow:#{ctx.user.id}"])
  end

  test "dead-letter poll settles when the callback never arrives", ctx do
    {transaction_id, _cri, pid} = checkout(ctx, 1)
    ref = Process.monitor(pid)

    # Skip the 60s grace period: trigger the poll directly. The Daraja sandbox
    # reports the payment as settled.
    send(pid, :poll_status)
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5_000

    assert Ledger.settled?(transaction_id)
    assert Ticketing.fulfilled?(transaction_id)
    assert inventory(ctx) == 99
  end
end
