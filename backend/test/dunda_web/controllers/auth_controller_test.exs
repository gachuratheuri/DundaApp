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

      assert %{"token" => token, "user" => %{"email" => email}} = json_response(conn, 200)
      assert is_binary(token) and byte_size(token) > 20
      assert email == "register-#{n}@example.com"
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
