defmodule DundaWeb.RbacTest do
  @moduledoc "Verifies portal admission, role permissions, and cross-tenant denial."
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
      |> Organisation.changeset(%{
        name: "RBAC Org #{n}",
        slug: "rbac-org-#{n}",
        verification_status: "verified",
        country: "KE"
      })
      |> Repo.insert()

    org
  end

  defp insert_member!(org, user, role) do
    {:ok, member} =
      %OrganisationMember{}
      |> OrganisationMember.changeset(%{
        organisation_id: org.id,
        user_id: user.id,
        role: role,
        accepted_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.insert()

    member
  end

  test "only mutation-capable organiser roles enter the portal" do
    org = insert_organisation!()

    for role <- @roles do
      user = insert_user!()
      insert_member!(org, user, role)

      assert DundaWeb.PortalAccess.allowed?(user) == role in ~w(owner admin manager)
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
      |> OrganisationMember.changeset(%{
        organisation_id: org.id,
        user_id: user.id,
        role: "superadmin"
      })

    refute changeset.valid?
  end

  describe "domain permission matrix" do
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

    test "scanner can admit but cannot enter the mutation-capable portal or manage events" do
      org = insert_organisation!()
      user = insert_user!()
      insert_member!(org, user, "scanner")

      refute DundaWeb.PortalAccess.allowed?(user)
      assert Dunda.Organisations.authorised?(user.id, org.id, :admission)
      refute Dunda.Organisations.authorised?(user.id, org.id, :manage_events)
      refute Dunda.Organisations.authorised?(user.id, org.id, :manage_payouts)
    end

    test "unknown permissions and cross-tenant resource identifiers fail closed" do
      org = insert_organisation!()
      other_org = insert_organisation!()
      user = insert_user!()
      insert_member!(org, user, "owner")

      refute Dunda.Organisations.authorised?(user.id, org.id, :not_a_permission)
      refute Dunda.Organisations.authorised?(user.id, other_org.id, :manage_payouts)
    end
  end
end
