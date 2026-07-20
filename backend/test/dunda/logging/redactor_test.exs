defmodule Dunda.Logging.RedactorTest do
  use ExUnit.Case, async: true

  alias Dunda.Logging.Redactor

  describe "redact/1" do
    test "redacts values under sensitive key names" do
      assert Redactor.redact(%{"password" => "hunter2", "name" => "ok"}) ==
               %{"password" => "[REDACTED]", "name" => "ok"}

      assert Redactor.redact(%{receipt: "QWE123RTY", quantity: 2}) ==
               %{receipt: "[REDACTED]", quantity: 2}
    end

    test "is case-insensitive and matches by substring on key names" do
      assert Redactor.redact(%{"Authorization" => "Bearer xyz"})["Authorization"] == "[REDACTED]"
      assert Redactor.redact(%{"PhoneNumber" => "254712345678"})["PhoneNumber"] == "[REDACTED]"
    end

    test "recurses into nested maps and lists" do
      nested = %{"outer" => %{"otp" => "123456", "safe" => "value"}, "list" => [%{"token" => "abc"}]}
      redacted = Redactor.redact(nested)
      assert redacted["outer"]["otp"] == "[REDACTED]"
      assert redacted["outer"]["safe"] == "value"
      assert [%{"token" => "[REDACTED]"}] = redacted["list"]
    end

    test "scrubs bearer tokens, JWTs, and Kenyan MSISDNs embedded in plain strings" do
      assert Redactor.redact("Authorization: Bearer abc123.def456") =~ "Bearer [REDACTED]"

      jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dQw4w9WgXcQ"
      assert Redactor.redact("token=#{jwt}") == "token=[REDACTED_JWT]"

      assert Redactor.redact("call 254712345678 now") == "call [REDACTED_MSISDN] now"
    end

    test "passes non-sensitive values through unchanged" do
      assert Redactor.redact(%{"status" => "completed", "amount_cents" => 1000}) ==
               %{"status" => "completed", "amount_cents" => 1000}

      assert Redactor.redact(42) == 42
      assert Redactor.redact(nil) == nil
      assert Redactor.redact(:atom_value) == :atom_value
    end

    test "does not attempt to redact struct fields (e.g. DateTime)" do
      now = DateTime.utc_now()
      assert Redactor.redact(now) == now
    end
  end

  describe "filter/2 (Erlang :logger primary filter)" do
    test "redacts sensitive metadata keys and leaves the rest of the log event intact" do
      event = %{level: :info, msg: {:string, "hello"}, meta: %{otp: "654321", request_id: "req-1"}}
      filtered = Redactor.filter(event, [])

      assert filtered.meta.otp == "[REDACTED]"
      assert filtered.meta.request_id == "req-1"
      assert filtered.level == :info
      assert filtered.msg == {:string, "hello"}
    end

    test "passes through log events without a metadata map unchanged" do
      event = %{level: :info, msg: {:string, "hello"}}
      assert Redactor.filter(event, []) == event
    end
  end

  test "install/0 is idempotent" do
    assert Redactor.install() == :ok
    assert Redactor.install() == :ok
  end
end
