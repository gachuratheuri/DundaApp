defmodule Dunda.Repo.Migrations.Phase4ReleaseApprovals do
  use Ecto.Migration

  def up do
    create table(:release_approvals, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :feature, :string, null: false
      add :approval_role, :string, null: false
      add :approver_ref, :string, null: false
      add :evidence_uri, :string, null: false
      add :canary_percent, :integer, null: false, default: 0
      add :approved_at, :utc_datetime, null: false
      add :expires_at, :utc_datetime, null: false
      add :revoked_at, :utc_datetime
      add :metadata, :map, null: false, default: %{}
      timestamps(updated_at: false)
    end

    # The approval ledger is append-only. Including approved_at permits an
    # approver to renew an expired approval without mutating historical
    # evidence, while still rejecting an exact duplicate insert.
    create unique_index(:release_approvals, [:feature, :approval_role, :approver_ref, :approved_at],
             where: "revoked_at IS NULL",
             name: :release_approvals_active_unique
           )
    create index(:release_approvals, [:feature, :expires_at])
    create constraint(:release_approvals, :release_approval_role_valid,
             check: "approval_role IN ('security', 'finance', 'operations')"
           )
    create constraint(:release_approvals, :release_approval_canary_valid,
             check: "canary_percent BETWEEN 0 AND 100"
           )
    create constraint(:release_approvals, :release_approval_expiry_order,
             check: "expires_at > approved_at"
           )
  end

  def down do
    drop table(:release_approvals)
  end
end
