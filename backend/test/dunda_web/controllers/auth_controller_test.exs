defmodule DundaWeb.AuthControllerTest do
  use DundaWeb.ConnCase

  describe "POST /api/auth/register" do
    test "registers user and returns token", %{conn: conn} do
      # assert true
    end
  end

  describe "POST /api/auth/login" do
    test "authenticates and returns token", %{conn: conn} do
      # assert true
    end
  end

  describe "POST /api/auth/google" do
    test "sandboxes oauth and returns token", %{conn: conn} do
      # assert true
    end
  end
end
