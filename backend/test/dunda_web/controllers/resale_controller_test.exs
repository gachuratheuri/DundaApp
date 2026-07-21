defmodule DundaWeb.ResaleControllerTest do
  use DundaWeb.ConnCase

  describe "POST /api/resale/listings" do
    test "rejects an unauthenticated listing mutation", %{conn: conn} do
      conn =
        post(conn, "/api/resale/listings", %{
          "ticket_id" => Ecto.UUID.generate(),
          "asking_price" => 100
        })

      assert conn.status in [401, 503]
    end
  end

  describe "POST /api/resale/listings/:id/intent" do
    test "rejects an unauthenticated purchase intent", %{conn: conn} do
      conn =
        post(conn, "/api/resale/listings/#{Ecto.UUID.generate()}/intent", %{
          "idempotency_key" => Base.encode16(:crypto.strong_rand_bytes(12))
        })

      assert conn.status in [401, 503]
    end
  end
end
