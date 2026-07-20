defmodule Dunda.AuditTest do
  use Dunda.DataCase, async: true

  alias Dunda.Audit

  test "redacts sensitive metadata before persistence" do
    assert {:ok, event} =
             Audit.record(%{
               action: "security.test",
               occurred_at: DateTime.utc_now() |> DateTime.truncate(:second),
               metadata: %{token: "never-store", nested: %{password: "also-secret", ok: "safe"}}
             })

    refute Map.has_key?(event.metadata, "token")
    assert event.metadata["nested"] == %{"ok" => "safe"}
  end

  test "audit rows are immutable at the database boundary" do
    assert {:ok, event} =
             Audit.record(%{
               action: "security.immutable",
               occurred_at: DateTime.utc_now() |> DateTime.truncate(:second)
             })

    assert_raise Postgrex.Error, ~r/audit_events are append-only/, fn ->
      Repo.update_all(from(e in Dunda.Audit.Event, where: e.id == ^event.id), set: [action: "tampered"])
    end
  end
end
