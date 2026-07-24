defmodule Dunda.Security.PasswordTest do
  use ExUnit.Case, async: true

  alias Dunda.Security.Password

  test "hashes with a versioned, salted PBKDF2 encoding and verifies exactly" do
    first = Password.hash("correct horse battery staple")
    second = Password.hash("correct horse battery staple")

    assert first != second
    assert String.starts_with?(first, "pbkdf2_sha256$600000$")
    refute Password.needs_rehash?(first)
    assert Password.verify("correct horse battery staple", first)
    refute Password.verify("incorrect", first)
  end

  test "malformed and attacker-inflated work factors fail closed" do
    refute Password.verify("password", "not-an-encoding")
    refute Password.verify("password", "pbkdf2_sha256$999999999$AA==$AA==")
    refute Password.verify("password", "pbkdf2_sha256$210000$AA==$AA==")
  end
end
