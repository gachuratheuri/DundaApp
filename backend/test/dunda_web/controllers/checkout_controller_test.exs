defmodule DundaWeb.CheckoutControllerTest do
  use DundaWeb.ConnCase, async: false

  alias Dunda.Accounts
  alias Dunda.Events
  alias Dunda.Ticketing.TicketTier

  setup %{conn: conn} do
    unique = System.unique_integer([:positive])

    {:ok, user} =
      Accounts.register_user(%{
        "email" => "checkout-#{unique}@example.com",
        "password" => "password123!",
        "name" => "Checkout Test"
      })

    {:ok, event} =
      Events.create_event(%{
        name: "Checkout Test #{unique}",
        venue: "Test Venue",
        starts_at: DateTime.utc_now() |> DateTime.add(30, :day) |> DateTime.truncate(:second),
        price_cents: 100_000,
        capacity: 50,
        status: "published",
        city: "Nairobi",
        currency: "KES"
      })

    tier =
      %TicketTier{}
      |> TicketTier.changeset(%{
        event_id: event.id,
        name: "VIP",
        price_cents: 250_000,
        capacity: 10,
        is_vip: true,
        max_per_order: 2
      })
      |> Dunda.Repo.insert!()

    %Dunda.Checkout.InventoryPool{}
    |> Dunda.Checkout.InventoryPool.changeset(%{
      pool_key: "tier:#{tier.id}",
      event_id: event.id,
      ticket_tier_id: tier.id,
      capacity: tier.capacity,
      reserved: 0,
      sold: 0,
      version: 1
    })
    |> Dunda.Repo.insert!()

    conn =
      put_req_header(conn, "authorization", "Bearer " <> DundaWeb.Auth.Token.sign(user))

    {:ok, conn: conn, user: user, event: event, tier: tier}
  end

  test "rejects unauthenticated checkout" do
    conn = post(build_conn(), "/api/checkout", %{"quote_id" => Ecto.UUID.generate()})
    assert %{"error" => %{"code" => _}} = json_response(conn, 401)
    refute conn.assigns[:current_user]
  end

  test "quote derives immutable economics from the server and ignores hostile price fields",
       ctx do
    conn =
      post(ctx.conn, "/api/quotes", %{
        "event_id" => to_string(ctx.event.id),
        "tier_id" => to_string(ctx.tier.id),
        "quantity" => 2,
        "amount" => 1,
        "unit_price_cents" => 1,
        "user_id" => -1
      })

    assert %{
             "data" => %{
               "quote_id" => quote_id,
               "quantity" => 2,
               "unit_price_cents" => 250_000,
               "total_cents" => 500_000,
               "currency" => "KES"
             }
           } = json_response(conn, 200)

    assert Dunda.Repo.get!(Dunda.Checkout.Quote, quote_id).user_id == ctx.user.id
  end

  test "checkout is quote-bound and an idempotency replay returns one intent", ctx do
    quote_conn =
      post(ctx.conn, "/api/quotes", %{
        "event_id" => to_string(ctx.event.id),
        "tier_id" => to_string(ctx.tier.id),
        "quantity" => 1
      })

    quote_id = json_response(quote_conn, 200)["data"]["quote_id"]
    key = "checkout-idempotency-#{System.unique_integer([:positive])}"

    request = fn ->
      ctx.conn
      |> put_req_header("idempotency-key", key)
      |> post("/api/checkout", %{"quote_id" => quote_id, "phone" => "0712345678"})
    end

    first = json_response(request.(), 202)["data"]
    second = json_response(request.(), 202)["data"]

    assert first["payment_intent_id"] == second["payment_intent_id"]
    assert first["amount_cents"] == 250_000
  end

  test "a quote cannot be consumed by another authenticated user", ctx do
    quote_conn =
      post(ctx.conn, "/api/quotes", %{
        "event_id" => to_string(ctx.event.id),
        "tier_id" => to_string(ctx.tier.id),
        "quantity" => 1
      })

    quote_id = json_response(quote_conn, 200)["data"]["quote_id"]
    unique = System.unique_integer([:positive])

    {:ok, other} =
      Accounts.register_user(%{
        "email" => "other-checkout-#{unique}@example.com",
        "password" => "password123!"
      })

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer " <> DundaWeb.Auth.Token.sign(other))
      |> put_req_header("idempotency-key", "cross-user-attempt-#{unique}")
      |> post("/api/checkout", %{"quote_id" => quote_id, "phone" => "0712345678"})

    assert %{"error" => %{"code" => "quote_user_mismatch"}} = json_response(conn, 422)
  end

  test "quote creation enforces tier maximum quantity", ctx do
    conn =
      post(ctx.conn, "/api/quotes", %{
        "event_id" => to_string(ctx.event.id),
        "tier_id" => to_string(ctx.tier.id),
        "quantity" => 3
      })

    assert %{"error" => %{"code" => "max_per_order_exceeded"}} = json_response(conn, 422)
  end

  test "checkout with missing idempotency key returns 422 rather than 500", ctx do
    quote_conn =
      post(ctx.conn, "/api/quotes", %{
        "event_id" => to_string(ctx.event.id),
        "tier_id" => to_string(ctx.tier.id),
        "quantity" => 1
      })

    quote_id = json_response(quote_conn, 200)["data"]["quote_id"]

    conn =
      post(ctx.conn, "/api/checkout", %{"quote_id" => quote_id, "phone" => "0712345678"})

    assert %{"error" => %{"code" => "idempotency_key_required"}} = json_response(conn, 422)
  end
end
