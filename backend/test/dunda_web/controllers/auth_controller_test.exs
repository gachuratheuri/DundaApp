defmodule DundaWeb.AuthControllerTest do
  use DundaWeb.ConnCase

  describe "POST /api/auth/register" do
    test "registers user and returns token", %{conn: conn} do
      n = System.unique_integer([:positive])

      conn =
        post(conn, "/api/auth/register", %{
          "email" => "register-#{n}@example.com",
          "password" => "password123!",
          "name" => "Registration Test"
        })

      assert %{
               "token" => token,
               "refresh_token" => refresh_token,
               "expires_in" => 900,
               "user" => %{"email" => email}
             } = json_response(conn, 200)

      assert is_binary(token) and byte_size(token) > 20
      assert is_binary(refresh_token) and byte_size(refresh_token) > 32
      assert email == "register-#{n}@example.com"
    end
  end

  describe "POST /api/auth/refresh" do
    test "rotates once and detects reuse of a replaced credential", %{conn: conn} do
      n = System.unique_integer([:positive])

      registered =
        conn
        |> post("/api/auth/register", %{
          "email" => "rotate-#{n}@example.com",
          "password" => "password123!",
          "name" => "Rotation Test",
          "device_id" => "test-device"
        })
        |> json_response(200)

      old_refresh = registered["refresh_token"]

      rotated =
        build_conn()
        |> post("/api/auth/refresh", %{
          "refresh_token" => old_refresh,
          "device_id" => "test-device"
        })
        |> json_response(200)

      refute rotated["refresh_token"] == old_refresh

      replay =
        post(build_conn(), "/api/auth/refresh", %{
          "refresh_token" => old_refresh,
          "device_id" => "test-device"
        })

      assert %{"error" => %{"code" => "invalid_session"}} = json_response(replay, 401)

      rejected_access =
        build_conn()
        |> put_req_header("authorization", "Bearer " <> rotated["access_token"])
        |> get("/api/tickets")

      assert json_response(rejected_access, 401)["error"]
    end
  end

  describe "POST /api/auth/login" do
    test "authenticates and returns token", %{conn: conn} do
      n = System.unique_integer([:positive])
      email = "login-#{n}@example.com"

      {:ok, _user} =
        Dunda.Accounts.register_user(%{
          "email" => email,
          "password" => "password123!",
          "name" => "Login Test"
        })

      conn = post(conn, "/api/auth/login", %{"email" => email, "password" => "password123!"})
      assert %{"token" => token} = json_response(conn, 200)
      assert is_binary(token) and byte_size(token) > 20
    end
  end

  describe "POST /api/auth/google" do
    test "remains hard-disabled during containment remediation", %{conn: conn} do
      conn = post(conn, "/api/auth/google", %{"token" => "untrusted"})
      assert %{"error" => %{"code" => "phase_0_containment"}} = json_response(conn, 503)
    end
  end
end
