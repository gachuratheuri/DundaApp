defmodule Dunda.Ticketing.EntitlementTest do
  use ExUnit.Case, async: true

  alias Dunda.Ticketing.Entitlement

  test "mint produces a verifiable token carrying a totp_secret" do
    {jwt, secret} = Entitlement.mint("tkt_1", claims: %{"event_id" => 1})

    assert [_h, _p, _s] = String.split(jwt, ".")
    assert {:ok, claims} = Entitlement.verify(jwt)
    assert claims["sub"] == "tkt_1"
    assert claims["event_id"] == 1
    assert claims["totp_secret"] == secret
  end

  test "verify rejects a tampered payload" do
    {jwt, _secret} = Entitlement.mint("tkt_2")
    [h, _p, s] = String.split(jwt, ".")
    forged_payload = Base.url_encode64(Jason.encode!(%{"sub" => "attacker"}), padding: false)

    assert {:error, _} = Entitlement.verify("#{h}.#{forged_payload}.#{s}")
  end
end
