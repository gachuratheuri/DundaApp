defmodule DundaWeb.CheckoutControllerTest do
  @moduledoc """
  Checkout API tests: identity binding (the buyer is always the authenticated
  user), tier resolution and its guardrails, and inventory reservation.

  Uses committed fixtures with the sandbox in `:auto` mode because the request
  path reads events through `Dunda.ReadRepo` and reserves inventory in a pool
  GenServer — both outside the test process's sandbox transaction.
  """
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Ecto.Query, only: [from: 2]

  @endpoint DundaWeb.Endpoint
  @moduletag :redis

  alias Dunda.Accounts
  alias Dunda.Events
  alias Dunda.Inventory
  alias Dunda.Ticketing.TicketTier

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Dunda.Repo, :auto)
    Ecto.Adapters.SQL.Sandbox.mode(Dunda.ReadRepo, :auto)

    suffix = System.unique_integer([:positive])

    {:ok, user} =
      Accounts.register_user(%{
        "email" => "checkout-#{suffix}@example.com",
        "password" => "password123!",
        "name" => "Checkout Test"
      })

    {:ok, event} =
      Events.create_event(%{
        name: "Checkout Test #{suffix}",
        venue: "Test Venue",
        starts_at: DateTime.utc_now() |> DateTime.add(30, :day) |> DateTime.truncate(:second),
        price_cents: 100_000,
        capacity: 50,
        status: "published",
        city: "Nairobi",
        currency: "KES"
      })

    {:ok, tier} =
      Dunda.Repo.insert(
        TicketTier.changeset(%TicketTier{}, %{
          event_id: event.id,
          name: "VIP",
          price_cents: 250_000,
          capacity: 10,
          is_vip: true,
          max_per_order: 2
        })
      )

    on_exit(fn ->
      # Kill any state machines the checkouts spawned so their later dead-letter
      # polls don't hit the DB after fixtures are gone.
      Dunda.Payments.TransactionSupervisor
      |> Horde.DynamicSupervisor.which_children()
      |> Enum.each(fn
        {_, pid, _, _} when is_pid(pid) -> Process.exit(pid, :kill)
        _ -> :ok
      end)

      Dunda.Repo.delete_all(from t in TicketTier, where: t.event_id == ^event.id)
      Dunda.Repo.delete_all(from e in Events.Event, where: e.id == ^event.id)
      Dunda.Repo.delete_all(from u in Accounts.User, where: u.id == ^user.id)

      Enum.each(
        [Inventory.event_pool(event.id), Inventory.tier_pool(tier.id)],
        fn pool ->
          {:ok, keys} = Redix.command(:redix, ["KEYS", "*#{pool}*"])
          Enum.each(keys, &Redix.command(:redix, ["DEL", &1]))
        end
      )

      Redix.command(:redix, ["DEL", "user_escrow:#{user.id}"])

      Ecto.Adapters.SQL.Sandbox.mode(Dunda.Repo, :manual)
    end)

    conn =
      build_conn()
      |> Plug.Conn.put_req_header("authorization", "Bearer " <> DundaWeb.Auth.Token.sign(user))

    {:ok, conn: conn, user: user, event: event, tier: tier}
  end

  defp await_key(key, attempts \\ 50) do
    case Redix.command(:redix, ["GET", key]) do
      {:ok, nil} when attempts > 0 ->
        Process.sleep(20)
        await_key(key, attempts - 1)

      {:ok, value} when is_binary(value) ->
        value

      other ->
        flunk("#{key} never appeared: #{inspect(other)}")
    end
  end

  test "rejects unauthenticated checkout", %{event: event} do
    conn =
      build_conn()
      |> post("/api/checkout", %{
        "event_id" => to_string(event.id),
        "phone" => "0712345678",
        "quantity" => 1
      })

    assert conn.status == 401
  end

  test "binds the purchase to the authenticated user, ignoring body user_id", ctx do
    conn =
      post(ctx.conn, "/api/checkout", %{
        "event_id" => to_string(ctx.event.id),
        # An attacker-controlled user_id must not become the buyer.
        "user_id" => "999999",
        "phone" => "0712345678",
        "quantity" => 1
      })

    assert %{"data" => %{"transaction_id" => txn_id, "status" => "pending"}} =
             json_response(conn, 202)

    # The state machine writes this key while handling the async :initiate
    # cast, so poll briefly rather than racing it.
    payload = await_key("checkout_request:ws_CO_SANDBOX_#{txn_id}")
    assert %{"user_id" => bound_user_id} = Jason.decode!(payload)
    assert to_string(bound_user_id) == to_string(ctx.user.id)
    refute to_string(bound_user_id) == "999999"
  end

  test "checkout defaults to the on-sale tier and reserves its pool", ctx do
    conn =
      post(ctx.conn, "/api/checkout", %{
        "event_id" => to_string(ctx.event.id),
        "phone" => "0712345678",
        "quantity" => 2
      })

    # Amount reflects the tier price (KSh 2500 × 2), not the event-level price.
    assert %{"data" => %{"amount" => 5000}} = json_response(conn, 202)

    # The reservation drew from the tier pool: 10 seeded − 2 escrowed.
    assert Inventory.remaining(Inventory.tier_pool(ctx.tier.id)) == 8
  end

  test "enforces the tier's max_per_order", ctx do
    conn =
      post(ctx.conn, "/api/checkout", %{
        "event_id" => to_string(ctx.event.id),
        "tier_id" => to_string(ctx.tier.id),
        "phone" => "0712345678",
        "quantity" => 3
      })

    assert %{"error" => %{"code" => "max_per_order_exceeded"}} = json_response(conn, 400)
  end

  test "does not sell around paused tiers via the event pool", ctx do
    {:ok, _} =
      Dunda.Repo.update(TicketTier.changeset(ctx.tier, %{status: "paused"}))

    conn =
      post(ctx.conn, "/api/checkout", %{
        "event_id" => to_string(ctx.event.id),
        "phone" => "0712345678",
        "quantity" => 1
      })

    assert %{"error" => %{"code" => "tier_not_on_sale"}} = json_response(conn, 400)
  end

  test "rejects a non-numeric tier_id cleanly", ctx do
    conn =
      post(ctx.conn, "/api/checkout", %{
        "event_id" => to_string(ctx.event.id),
        "tier_id" => "tier_abc",
        "phone" => "0712345678",
        "quantity" => 1
      })

    assert %{"error" => %{"code" => "invalid_request"}} = json_response(conn, 422)
  end
end
