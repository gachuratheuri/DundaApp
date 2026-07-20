defmodule Dunda.Repo.Migrations.OrganisationsMembersPayouts do
  @moduledoc """
  Builds out the Organiser side of the lifecycle (Portal onboarding, team, and
  payouts):

  * `organisations` gains the OnboardingLive fields — owner, branding, the
    M-Pesa till used for collections, a `verification_status` (KYC gate before
    going live), and the agreement acceptance timestamp.
  * `organisation_members` — TeamLive membership + RBAC (owner/admin/manager/
    scanner). The `scanner` role is what a gate device authenticates as.
  * `payouts` — the B2C disbursement ledger surfaced in PayoutsLive, written by
    `PayoutWorker`. Idempotent on the Daraja B2C conversation id.
  """
  use Ecto.Migration

  def change do
    alter table(:organisations) do
      add :owner_user_id, references(:users, on_delete: :nilify_all)
      add :description, :text
      add :logo_url, :string
      add :support_email, :string
      # M-Pesa Paybill/Till for collections (distinct from the B2C payout phone).
      add :mpesa_till_number, :string
      # KYC gate: pending -> verified -> suspended.
      add :verification_status, :string, null: false, default: "pending"
      add :agreement_accepted_at, :utc_datetime
      add :country, :string, null: false, default: "KE"
    end

    create index(:organisations, [:owner_user_id])

    create constraint(:organisations, :organisations_verification_valid,
             check: "verification_status IN ('pending', 'verified', 'suspended')"
           )

    create table(:organisation_members) do
      add :organisation_id, references(:organisations, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :role, :string, null: false, default: "member"
      add :invited_at, :utc_datetime
      add :accepted_at, :utc_datetime

      timestamps()
    end

    create unique_index(:organisation_members, [:organisation_id, :user_id])
    create index(:organisation_members, [:user_id])

    create constraint(:organisation_members, :organisation_members_role_valid,
             check: "role IN ('owner', 'admin', 'manager', 'scanner', 'member')"
           )

    create table(:payouts) do
      add :organisation_id, references(:organisations, on_delete: :nilify_all), null: false
      add :amount_cents, :integer, null: false
      add :currency, :string, null: false, default: "KES"
      add :mpesa_phone, :string, null: false
      # pending -> processing -> paid / failed.
      add :status, :string, null: false, default: "pending"
      add :b2c_conversation_id, :string
      add :b2c_receipt, :string
      add :failure_reason, :string
      # Settlement window this payout covers.
      add :period_start, :utc_datetime
      add :period_end, :utc_datetime
      add :paid_at, :utc_datetime

      timestamps()
    end

    create index(:payouts, [:organisation_id, :status])
    # Idempotency: a Daraja B2C result reconciles exactly one payout row.
    create unique_index(:payouts, [:b2c_conversation_id],
             where: "b2c_conversation_id IS NOT NULL"
           )

    create constraint(:payouts, :payouts_amount_positive, check: "amount_cents > 0")

    create constraint(:payouts, :payouts_status_valid,
             check: "status IN ('pending', 'processing', 'paid', 'failed')"
           )
  end
end
