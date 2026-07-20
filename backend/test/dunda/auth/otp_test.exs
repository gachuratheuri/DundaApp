defmodule Dunda.Auth.OTPTest do
  use ExUnit.Case, async: true

  test "rejects invalid phone numbers and malformed codes" do
    assert {:error, :invalid_otp} = Dunda.Auth.OTP.verify_code("not-a-phone", "000000")
    assert {:error, :invalid_otp} = Dunda.Auth.OTP.verify_code("0712345678", "0000")
  end
end
