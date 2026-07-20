defmodule Dunda.Ticketing.Phase7ProtocolTest do
  use ExUnit.Case, async: true

  alias Dunda.Ticketing.{ManifestProtocol, Ticket}

  test "manifest signatures verify with the distributed public key" do
    payload = %{protocol_version: 2, event_id: 42, revocations: [], tickets: []}
    signature = ManifestProtocol.sign(payload)
    assert ManifestProtocol.verify(payload, signature)
    refute ManifestProtocol.verify(Map.put(payload, :event_id, 43), signature)
  end

  test "protocol-v2 ticket changesets require a complete device binding" do
    attrs = %{credential_version: 2, credential_public_key: :binary.copy(<<1>>, 32), credential_valid_from: ~U[2026-07-20 10:00:00Z], credential_valid_until: ~U[2026-07-20 12:00:00Z], credential_bound_at: ~U[2026-07-20 09:00:00Z], credential_epoch: 1}
    assert Ticket.changeset(%Ticket{}, attrs).valid? == false
    complete = Map.merge(%{tier_label: "GENERAL", price_kes: 1, status: "valid", user_id: 1, event_id: 1}, attrs)
    assert Ticket.changeset(%Ticket{}, complete).valid?
  end
end
