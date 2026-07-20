defmodule DundaWeb.PrivacyControllerTest do
  use DundaWeb.ConnCase, async: true

  import Dunda.ContractCase

  alias Dunda.Accounts.{Privacy, User}

  defp insert_user! do
    n = System.unique_integer([:positive])

    {:ok, user} =
      Dunda.Accounts.register_user(%{
        "email" => "privacy-#{n}@example.com",
        "password" => "password123!",
        "name" => "Privacy Test"
      })

    user
  end

  defp authed_conn(conn, user) do
    Plug.Conn.put_req_header(conn, "authorization", "Bearer " <> DundaWeb.Auth.Token.sign(user))
  end

  describe "PATCH /api/privacy/requests/:id" do
    test "applies a rectification and completes the request", %{conn: conn} do
      user = insert_user!()
      {:ok, request} = Privacy.create_request(user.id, "rectification", user.email)

      conn = conn |> authed_conn(user) |> patch("/api/privacy/requests/#{request.id}", %{"name" => "Rectified Name"})
      body = json_response(conn, 200)

      assert %{"data" => %{"status" => "completed"}} = body
      assert Dunda.Repo.get!(User, user.id).name == "Rectified Name"
      assert_matches_contract("updatePrivacyRequest", 200, body)
    end

    test "records an objection without deleting anything", %{conn: conn} do
      user = insert_user!()
      {:ok, request} = Privacy.create_request(user.id, "objection", user.email)

      conn = conn |> authed_conn(user) |> patch("/api/privacy/requests/#{request.id}", %{"scope" => "analytics"})
      body = json_response(conn, 200)

      assert %{"data" => %{"status" => "in_progress"}} = body
      assert Dunda.Repo.get!(User, user.id).id == user.id
      assert_matches_contract("updatePrivacyRequest", 200, body)
    end

    test "returns 404 for a request that belongs to another user", %{conn: conn} do
      owner = insert_user!()
      attacker = insert_user!()
      {:ok, request} = Privacy.create_request(owner.id, "rectification", owner.email)

      conn = conn |> authed_conn(attacker) |> patch("/api/privacy/requests/#{request.id}", %{"name" => "Hijacked"})

      assert json_response(conn, 404)
      assert Dunda.Repo.get!(User, owner.id).name != "Hijacked"
    end

    test "returns 422 for a request type that is not client-updatable", %{conn: conn} do
      user = insert_user!()
      {:ok, request} = Privacy.create_request(user.id, "erasure", user.email)

      conn = conn |> authed_conn(user) |> patch("/api/privacy/requests/#{request.id}", %{})

      assert json_response(conn, 422)
    end

    test "rejects an unauthenticated request", %{conn: conn} do
      user = insert_user!()
      {:ok, request} = Privacy.create_request(user.id, "rectification", user.email)

      conn = patch(conn, "/api/privacy/requests/#{request.id}", %{"name" => "x"})
      assert conn.status == 401
    end
  end
end
