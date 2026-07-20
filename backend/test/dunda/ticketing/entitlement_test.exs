defmodule Dunda.Ticketing.EntitlementTest do
  use ExUnit.Case, async: true

  alias Dunda.Ticketing.Entitlement

  test "mint produces a JWS token carrying an encrypted totp_secret and verifies correctly" do
    {jwt, secret} = Entitlement.mint("tkt_1", claims: %{"event_id" => 1})

    assert [_h, _p, _s] = String.split(jwt, ".")
    assert {:ok, claims} = Entitlement.verify(jwt)
    assert claims["sub"] == "tkt_1"
    assert claims["event_id"] == 1

    # Decrypt and verify matching plaintext secret
    assert {:ok, encrypted_secret_bin} = Base.url_decode64(claims["totp_secret"], padding: false)
    assert Dunda.Vault.decrypt!(encrypted_secret_bin) == secret

    # Generate current TOTP code and verify
    now = System.system_time(:second)
    totp = generate_totp_for_test(secret, div(now, 30))
    assert {:ok, ^claims} = Entitlement.verify_with_totp(jwt, totp)
    assert {:error, :invalid_totp} = Entitlement.verify_with_totp(jwt, "000000")
  end

  test "verify rejects a tampered payload" do
    {jwt, _secret} = Entitlement.mint("tkt_2")
    [h, _p, s] = String.split(jwt, ".")
    forged_payload = Base.url_encode64(Jason.encode!(%{"sub" => "attacker"}), padding: false)

    assert {:error, _} = Entitlement.verify("#{h}.#{forged_payload}.#{s}")
  end

  # Test-only helper to generate TOTP code matching entitlement.ex implementation
  defp generate_totp_for_test(secret, counter) do
    import Bitwise
    msg = <<counter::integer-size(64)-big>>
    {:ok, raw_secret} = Base.url_decode64(secret, padding: false)
    hmac = :crypto.mac(:hmac, :sha, raw_secret, msg)
    <<_::binary-size(19), last::integer-size(8)>> = hmac
    offset = last &&& 0x0F
    <<_::binary-size(offset), byte1::integer-size(8), byte2::integer-size(8), byte3::integer-size(8), byte4::integer-size(8), _::binary>> = hmac
    binary =
      ((byte1 &&& 0x7F) <<< 24)
      ||| (byte2 <<< 16)
      ||| (byte3 <<< 8)
      ||| byte4
    code = rem(binary, 1_000_000)
    to_string(code) |> String.pad_leading(6, "0")
  end
end
