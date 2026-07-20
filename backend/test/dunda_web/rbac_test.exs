defmodule DundaWeb.RbacTest do
  @moduledoc """
  Characterises the CURRENT state of organiser-portal role enforcement —
  corrected after an initial pass of this test overclaimed the gap (see the
  correction note at the end of this moduledoc; leaving it in rather than
  quietly rewriting history).

  `Dunda.Organisations.OrganisationMember` declares five roles (`owner admin
  manager scanner member`), matching the permission model the root
  remediation plan's Phase 2 specifies. `Dunda.Organisations.member?/3` is a
  real, working role-filter primitive (`m.role in ^roles`), and it IS used
  — in exactly one place: `event_editor_live.ex`'s update path gates
  editing an existing event to `~w(owner admin manager)`. That is the only
  role-conditional logic found anywhere in `lib/dunda_web/`.

  Two things remain true and are what this test actually asserts:

    1. **Portal entry itself is not role-gated.** `DundaWeb.PortalAccess.allowed?/1`
       (used by `DundaWeb.Plugs.OrganiserAuthPlug` and the LiveView
       `on_mount` hook, `DundaWeb.OrganiserAuth`) grants access to ANY
       active member regardless of role — a `scanner` role member reaches
       every LiveView a `manager` does; `member?/3` is not consulted at
       entry, only inside the one update-event action.
    2. **Every other mutating action is unguarded by role**: event
       creation, payouts, team management, the scraper config, extras,
       and tickets have no `member?/3` call or equivalent anywhere.

  This is recorded as a **High** (downgraded from an earlier, inaccurate
  "Critical, zero role checks exist anywhere" characterization — corrected
  in `docs/phase_12_verification_observability_rollout.md` § Findings and
  pen-test tracking, finding F2) open finding — implementing real per-role
  authorization across every mutating action is Phase 2 scope this session
  did not undertake (it requires LiveView-level verification this sandbox
  cannot run). The purpose of this test is to make the gap loud and
  CI-visible: once broader enforcement lands, the relevant assertions below
  should flip and this moduledoc should describe the enforced matrix
  instead of the gap.
  """
  use Dunda.DataCase, async: true

  alias Dunda.Organisations.{Organisation, OrganisationMember}

  @roles ~w(owner admin manager scanner member)

  defp insert_user! do
    n = System.unique_integer([:positive])

    {:ok, user} =
      Dunda.Accounts.register_user(%{
        "email" => "rbac-#{n}@example.com",
        "password" => "password123!",
        "name" => "RBAC Test"
      })

    user
  end

  defp insert_organisation! do
    n = System.unique_integer([:positive])

    {:ok, org} =
      %Organisation{}
      |> Organisation.changeset(%{name: "RBAC Org #{n}", slug: "rbac-org-#{n}", verification_status: "verified", country: "KE"})
      |> Repo.insert()

    org
  end

  defp insert_member!(org, user, role) do
    {:ok, member} =
      %OrganisationMember{}
      |> OrganisationMember.changeset(%{organisation_id: org.id, user_id: user.id, role: role})
      |> Repo.insert()

    member
  end

  test "every declared role currently grants identical portal access (gap, not a guarantee)" do
    org = insert_organisation!()

    for role <- @roles do
      user = insert_user!()
      insert_member!(org, user, role)

      assert DundaWeb.PortalAccess.allowed?(user),
             "role=#{role} unexpectedly denied — if this now fails because role enforcement was added, " <>
               "update this test to assert the correct per-role outcome and remove this characterization test"
    end
  end

  test "a user with no membership at all is denied, regardless of the role taxonomy existing" do
    user = insert_user!()
    refute DundaWeb.PortalAccess.allowed?(user)
  end

  test "OrganisationMember rejects a role outside the declared taxonomy" do
    org = insert_organisation!()
    user = insert_user!()

    changeset =
      %OrganisationMember{}
      |> OrganisationMember.changeset(%{organisation_id: org.id, user_id: user.id, role: "superadmin"})

    refute changeset.valid?
  end

  describe "Dunda.Organisations.member?/3 — the one real enforcement primitive, and its one call site's scope" do
    test "grants for a role in the requested list" do
      org = insert_organisation!()
      user = insert_user!()
      insert_member!(org, user, "manager")

      assert Dunda.Organisations.member?(user.id, org.id, ~w(owner admin manager))
    end

    test "denies for a role outside the requested list — this is the check event_editor_live.ex relies on to keep scanner/member out of event edits" do
      org = insert_organisation!()
      user = insert_user!()
      insert_member!(org, user, "scanner")

      refute Dunda.Organisations.member?(user.id, org.id, ~w(owner admin manager))
    end

    test "denies a member of a DIFFERENT organisation regardless of role (tenant isolation holds here)" do
      org = insert_organisation!()
      other_org = insert_organisation!()
      user = insert_user!()
      insert_member!(other_org, user, "owner")

      refute Dunda.Organisations.member?(user.id, org.id, ~w(owner admin manager))
    end

    test "but PortalAccess.allowed?/1 — the actual portal-entry gate — does not consult roles at all, so a scanner still reaches every LiveView member?/3 is never checked in" do
      org = insert_organisation!()
      user = insert_user!()
      insert_member!(org, user, "scanner")

      assert DundaWeb.PortalAccess.allowed?(user)
      refute Dunda.Organisations.member?(user.id, org.id, ~w(owner admin manager))
    end
  end
end
