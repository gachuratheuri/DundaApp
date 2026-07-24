defmodule Dunda.Ticketing.Phase7ProtocolTest do
  use ExUnit.Case, async: true

  alias Dunda.Ticketing.{ManifestProtocol, Ticket}

  test "manifest signatures verify with the distributed public key" do
    payload = %{protocol_version: 2, event_id: 42, revocations: [], tickets: []}

    document =
      ManifestProtocol.signed_document(
        42,
        1,
        "manifest-v1",
        "2026-01-01T00:00:00Z",
        "2026-01-02T00:00:00Z",
        payload
      )

    signature = ManifestProtocol.sign(document)
    assert ManifestProtocol.verify(document, signature)
    refute ManifestProtocol.verify(Map.put(document, :version, 2), signature)
  end

  test "protocol-v2 ticket changesets require a complete device binding" do
    attrs = %{
      credential_version: 2,
      credential_public_key: :binary.copy(<<1>>, 32),
      credential_valid_from: ~U[2026-07-20 10:00:00Z],
      credential_valid_until: ~U[2026-07-20 12:00:00Z],
      credential_bound_at: ~U[2026-07-20 09:00:00Z],
      credential_epoch: 1
    }

    assert Ticket.changeset(%Ticket{}, attrs).valid? == false

    complete =
      Map.merge(
        %{tier_label: "GENERAL", price_cents: 100, status: "valid", user_id: 1, event_id: 1},
        attrs
      )

    assert Ticket.changeset(%Ticket{}, complete).valid?
  end
end
