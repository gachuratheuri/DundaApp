defmodule Dunda.Payments.Daraja.SandboxTest do
  use ExUnit.Case, async: true

  alias Dunda.Payments.Daraja.Sandbox

  test "stk_push echoes the idempotency key into the checkout id" do
    assert {:ok, "ws_CO_SANDBOX_abc123"} = Sandbox.stk_push("254712345678", 1500, "abc123")
  end

  test "query_status reports a settled, receipted transaction" do
    assert {:ok, %{"ResultCode" => "0", "MpesaReceiptNumber" => receipt}} =
             Sandbox.query_status("ws_CO_SANDBOX_abc123")

    assert String.starts_with?(receipt, "SANDBOX")
  end
end
