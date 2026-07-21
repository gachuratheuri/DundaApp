defmodule Dunda.Ticketing.CredentialProtocolTest do
  use ExUnit.Case, async: true

  alias Dunda.Ticketing.CredentialProtocol

  @vector %{
    ticket_id: "ticket-001",
    event_id: "42",
    time_step: 57_600_000,
    nonce: Base.url_decode64!("ABEiM0RVZneImaq7zN3u_w", padding: false),
    credential_public_key:
      Base.url_decode64!("11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaaPcHURo", padding: false),
    signature:
      Base.url_decode64!(
        "3bG11yTivfz4rdoDYaB2H9ULh4r-vbjRjC9FBC7Dl6M76S1q3k2uMIUrItYDSpbZFSHMbmKFqNlGFm9mW_ykDA",
        padding: false
      )
  }

  test "canonical proof matches the published cross-language vector" do
    assert CredentialProtocol.canonical_proof(@vector) ==
             "dunda-ticket-proof\nv=2\nticket_id=ticket-001\nevent_id=42\ntime_step=57600000\nnonce=ABEiM0RVZneImaq7zN3u_w\ncredential_public_key=11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaaPcHURo"

    assert CredentialProtocol.verify_device_signature(
             @vector.credential_public_key,
             CredentialProtocol.canonical_proof(@vector),
             @vector.signature
           )
  end

  test "time windows reject stale proofs and permit one-step drift" do
    assert CredentialProtocol.valid_time_step?(100, 3_000, 1)
    refute CredentialProtocol.valid_time_step?(100, 3_060, 1)
  end

  test "nonce and signature sizes are strict" do
    refute CredentialProtocol.valid_public_key?(:binary.copy(<<0>>, 31))
    refute CredentialProtocol.valid_signature?(:binary.copy(<<0>>, 63))
  end
end
