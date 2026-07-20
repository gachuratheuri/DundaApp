defmodule Dunda.ReleaseApprovalTest do
  use ExUnit.Case, async: true

  alias Dunda.ReleaseApproval

  test "requires future expiry, evidence, and a recognised approval role" do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    changeset =
      ReleaseApproval.changeset(%ReleaseApproval{}, %{
        feature: "checkout",
        approval_role: "security",
        approver_ref: "reviewer-1",
        evidence_uri: "https://evidence.invalid/review/1",
        approved_at: now,
        expires_at: DateTime.add(now, 86_400, :second),
        canary_percent: 10
      })

    assert changeset.valid?
  end

  test "rejects an expired approval" do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    changeset =
      ReleaseApproval.changeset(%ReleaseApproval{}, %{
        feature: "checkout",
        approval_role: "security",
        approver_ref: "reviewer-1",
        evidence_uri: "https://evidence.invalid/review/1",
        approved_at: DateTime.add(now, -86_400, :second),
        expires_at: DateTime.add(now, -1, :second),
        canary_percent: 100
      })

    refute changeset.valid?
  end

  test "rejects approvals dated in the future and canonicalises operator input" do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    changeset =
      ReleaseApproval.changeset(%ReleaseApproval{}, %{
        feature: " checkout ",
        approval_role: " security ",
        approver_ref: " reviewer-1 ",
        evidence_uri: " https://evidence.invalid/review/1 ",
        approved_at: DateTime.add(now, 60, :second),
        expires_at: DateTime.add(now, 86_400, :second),
        canary_percent: 100
      })

    refute changeset.valid?
    assert changeset.changes.feature == "checkout"
    assert changeset.changes.approval_role == "security"
  end
end
