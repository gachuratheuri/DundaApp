defmodule Dunda.Auth.GoogleVerifierTest do
  use ExUnit.Case, async: true

  test "rejects malformed and oversized tokens without network access" do
    assert {:error, :invalid_google_token} = Dunda.Auth.GoogleVerifier.verify("")

    assert {:error, :invalid_google_token} =
             Dunda.Auth.GoogleVerifier.verify(String.duplicate("x", 4097))
  end
end
