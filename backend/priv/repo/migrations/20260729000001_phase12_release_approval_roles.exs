defmodule Dunda.Repo.Migrations.Phase12ReleaseApprovalRoles do
  use Ecto.Migration

  def up do
    # CHECK constraints cannot be altered in place; drop and recreate with
    # the extended role set (Phase 12 §12.12 — product and privacy sign-off
    # now required, matching the root plan's G12 five-stakeholder gate).
    drop constraint(:release_approvals, :release_approval_role_valid)

    create constraint(:release_approvals, :release_approval_role_valid,
             check: "approval_role IN ('security', 'finance', 'operations', 'product', 'privacy')"
           )
  end
end
