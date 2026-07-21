defmodule Dunda.ReleaseApprovalsGovernanceTest do
  use ExUnit.Case, async: true

  alias Dunda.ReleaseApproval
  alias Dunda.ReleaseApprovals

  test "the five G12 governance roles are all recognised by the schema" do
    for role <- ~w(security finance operations product privacy) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      changeset =
        ReleaseApproval.changeset(%ReleaseApproval{}, %{
          feature: "checkout",
          approval_role: role,
          approver_ref: "reviewer-1",
          evidence_uri: "https://evidence.invalid/review/1",
          approved_at: now,
          expires_at: DateTime.add(now, 86_400, :second),
          canary_percent: 10
        })

      assert changeset.valid?, "expected role=#{role} to be a valid approval_role"
    end
  end

  test "rejects a role outside the five-role governance set" do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    changeset =
      ReleaseApproval.changeset(%ReleaseApproval{}, %{
        feature: "checkout",
        approval_role: "legal",
        approver_ref: "reviewer-1",
        evidence_uri: "https://evidence.invalid/review/1",
        approved_at: now,
        expires_at: DateTime.add(now, 86_400, :second),
        canary_percent: 10
      })

    refute changeset.valid?
  end

  describe "rollback_threshold_breached?/1" do
    test "false when everything is healthy and no gauges are set" do
      refute ReleaseApprovals.rollback_threshold_breached?(%{})
    end

    test "true when the release-health error rate is over threshold" do
      counters = %{
        {:requests_total, "/api/events", 200} => 1,
        {:requests_total, "/api/events", 500} => 1,
        {:request_duration_us_total, "/api/events"} => 100,
        {:request_duration_count, "/api/events"} => 1
      }

      assert ReleaseApprovals.rollback_threshold_breached?(counters)
    end

    test "true when reconciliation_diff_count is positive" do
      assert ReleaseApprovals.rollback_threshold_breached?(%{
               {:gauge, :reconciliation_diff_count} => 1
             })
    end

    test "true when dsr_requests_overdue is positive" do
      assert ReleaseApprovals.rollback_threshold_breached?(%{{:gauge, :dsr_requests_overdue} => 3})
    end

    test "false when gauges are present but zero" do
      counters = %{
        {:gauge, :reconciliation_diff_count} => 0,
        {:gauge, :dsr_requests_overdue} => 0
      }

      refute ReleaseApprovals.rollback_threshold_breached?(counters)
    end
  end
end
