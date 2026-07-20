defmodule Dunda.Security.StepUpTest do
  use ExUnit.Case, async: true

  alias Dunda.Security.StepUp

  test "issues short-lived purpose-bound capabilities" do
    token = StepUp.issue(42, "payout_destination")

    assert {:ok, 42} = StepUp.verify(token, "payout_destination")
    assert {:error, :invalid_step_up} = StepUp.verify(token, "other_purpose")
  end

  test "tampering is rejected" do
    token = StepUp.issue(42, "payout_destination")
    <<head::binary-size(byte_size(token) - 1), _last>> = token

    assert {:error, :invalid_step_up} = StepUp.verify(head <> "x", "payout_destination")
  end
end
