defmodule Dunda.ContainmentTest do
  use ExUnit.Case, async: false

  alias Dunda.Containment

  setup do
    previous_mode = Application.get_env(:dunda, :containment_mode)
    previous_gate = Application.get_env(:dunda, :phase4_gate_enforced)
    previous_emails = Application.get_env(:dunda, :portal_admin_emails)
    previous_ids = Application.get_env(:dunda, :portal_admin_user_ids)

    on_exit(fn ->
      Application.put_env(:dunda, :containment_mode, previous_mode)
      Application.put_env(:dunda, :phase4_gate_enforced, previous_gate)
      Application.put_env(:dunda, :portal_admin_emails, previous_emails)
      Application.put_env(:dunda, :portal_admin_user_ids, previous_ids)
    end)

    :ok
  end

  test "keeps globally guarded features blocked until Phase 4 is explicitly disabled or approved" do
    Application.put_env(:dunda, :containment_mode, false)
    Application.put_env(:dunda, :phase4_gate_enforced, true)

    assert Containment.blocked?(:checkout)
    assert Containment.portal_mutations_blocked?()

    Application.put_env(:dunda, :phase4_gate_enforced, false)

    refute Containment.blocked?(:checkout)
    refute Containment.portal_mutations_blocked?()
  end

  test "blocks every Phase 0 side-effect feature" do
    Application.put_env(:dunda, :containment_mode, true)

    for feature <- Containment.blocked_features() do
      assert Containment.blocked?(feature)
    end

    assert Containment.portal_mutations_blocked?()
  end

  test "allow-list matching is exact, case-insensitive, and fail-closed" do
    Application.put_env(:dunda, :containment_mode, true)
    Application.put_env(:dunda, :portal_admin_emails, ["Admin@Example.test"])
    Application.put_env(:dunda, :portal_admin_user_ids, [42])

    assert Containment.portal_allowed?(%{id: 7, email: "admin@example.test"})
    assert Containment.portal_allowed?(%{id: 42, email: "unknown@example.test"})
    refute Containment.portal_allowed?(%{id: 7, email: "admin@example.test.evil"})
    refute Containment.portal_allowed?(%{id: 7, email: nil})
    refute Containment.portal_allowed?(nil)
  end
end
