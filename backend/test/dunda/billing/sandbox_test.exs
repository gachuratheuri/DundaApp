defmodule Dunda.Billing.SandboxTest do
  use Dunda.DataCase

  alias Dunda.Billing.Pesapal.Sandbox

  describe "sandbox confirmation flow" do
    test "returns a provider-shaped completed transaction without network access" do
      assert {:ok, response} = Sandbox.transaction_status("sandbox-order-1")
      assert response["order_tracking_id"] == "sandbox-order-1"
      assert response["status_code"] == 1
      assert response["payment_status_description"] == "Completed"
    end
  end
end
