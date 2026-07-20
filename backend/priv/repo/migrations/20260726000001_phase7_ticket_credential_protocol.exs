defmodule Dunda.Repo.Migrations.Phase7TicketCredentialProtocol do
  use Ecto.Migration

  @moduledoc """
  Adds the versioned, device-bound ticket protocol and the venue-local
  coordinator audit model. Existing TOTP credentials remain historical only;
  protocol v2 is the only credential accepted by the new admission context.
  """

  def up do
    alter table(:tickets) do
      add :credential_version, :integer, null: false, default: 1
      add :credential_public_key, :binary
      add :credential_valid_from, :utc_datetime
      add :credential_valid_until, :utc_datetime
      add :credential_bound_at, :utc_datetime
      add :credential_epoch, :integer, null: false, default: 0
    end

    create index(:tickets, [:event_id, :credential_version, :credential_epoch])
    create constraint(:tickets, :ticket_credential_version_valid,
             check: "credential_version IN (1, 2) AND credential_epoch >= 0"
           )
    create constraint(:tickets, :ticket_v2_credential_complete,
             check: "credential_version = 1 OR (credential_public_key IS NOT NULL AND octet_length(credential_public_key) = 32 AND credential_valid_from IS NOT NULL AND credential_valid_until IS NOT NULL AND credential_valid_until > credential_valid_from AND credential_bound_at IS NOT NULL)"
           )
    execute """
    CREATE OR REPLACE FUNCTION dunda_ticket_credential_epoch_guard() RETURNS trigger AS $$
    BEGIN
      IF OLD.credential_version = 2 AND NEW.credential_public_key IS DISTINCT FROM OLD.credential_public_key AND NEW.credential_epoch <= OLD.credential_epoch THEN
        RAISE EXCEPTION 'ticket credential key changes require a strictly increasing credential epoch';
      END IF;
      RETURN NEW;
    END; $$ LANGUAGE plpgsql;
    CREATE TRIGGER ticket_credential_epoch_guard BEFORE UPDATE ON tickets
      FOR EACH ROW EXECUTE FUNCTION dunda_ticket_credential_epoch_guard();
    """

    create table(:scanner_devices, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :organisation_id, references(:organisations, on_delete: :restrict), null: false
      add :event_id, references(:events, on_delete: :restrict)
      add :operator_user_id, references(:users, on_delete: :restrict), null: false
      add :device_name, :string, null: false
      add :device_public_key, :binary, null: false
      add :key_fingerprint, :string, null: false
      add :status, :string, null: false, default: "active"
      add :last_seen_at, :utc_datetime
      add :revoked_at, :utc_datetime
      add :revocation_reason, :string
      timestamps()
    end

    create unique_index(:scanner_devices, [:key_fingerprint])
    create index(:scanner_devices, [:organisation_id, :event_id, :status])
    create constraint(:scanner_devices, :scanner_device_key_valid,
             check: "octet_length(device_public_key) = 32"
           )
    create constraint(:scanner_devices, :scanner_device_status_valid,
             check: "status IN ('active', 'suspended', 'revoked')"
           )

    create table(:event_manifests, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :event_id, references(:events, on_delete: :restrict), null: false
      add :version, :integer, null: false
      add :key_id, :string, null: false
      add :payload, :map, null: false, default: %{}
      add :payload_hash, :string, null: false
      add :signature, :binary, null: false
      add :valid_from, :utc_datetime, null: false
      add :valid_until, :utc_datetime, null: false
      add :published_at, :utc_datetime
      add :revoked_at, :utc_datetime
      timestamps(updated_at: false)
    end

    create unique_index(:event_manifests, [:event_id, :version])
    create index(:event_manifests, [:event_id, :valid_from, :valid_until])
    create constraint(:event_manifests, :event_manifest_version_valid, check: "version > 0")
    create constraint(:event_manifests, :event_manifest_window_valid, check: "valid_until > valid_from")
    create constraint(:event_manifests, :event_manifest_payload_bounded, check: "octet_length(payload::text) <= 10000000")

    create table(:scanner_admissions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :admission_id, :string, null: false
      add :ticket_id, references(:tickets, type: :binary_id, on_delete: :restrict), null: false
      add :event_id, references(:events, on_delete: :restrict), null: false
      add :scanner_device_id, references(:scanner_devices, type: :binary_id, on_delete: :restrict), null: false
      add :manifest_version, :integer, null: false
      add :protocol_version, :integer, null: false
      add :time_step, :bigint, null: false
      add :proof_nonce, :binary, null: false
      add :proof_signature, :binary, null: false
      add :request_nonce, :binary, null: false
      add :request_signature, :binary, null: false
      add :gate, :string
      add :result, :string, null: false
      add :reason, :string
      add :clock_offset_seconds, :integer
      add :observed_at, :utc_datetime, null: false
      add :coordinator_received_at, :utc_datetime, null: false
      add :uploaded_at, :utc_datetime
      timestamps(updated_at: false)
    end

    create unique_index(:scanner_admissions, [:admission_id])
    create unique_index(:scanner_admissions, [:ticket_id, :proof_nonce])
    create unique_index(:scanner_admissions, [:ticket_id], where: "result = 'admitted'", name: :scanner_admissions_single_admission)
    create index(:scanner_admissions, [:event_id, :coordinator_received_at])
    create constraint(:scanner_admissions, :scanner_admission_protocol_valid, check: "protocol_version = 2")
    create constraint(:scanner_admissions, :scanner_admission_result_valid,
             check: "result IN ('admitted', 'rejected', 'duplicate', 'manual_review')"
           )
    create constraint(:scanner_admissions, :scanner_admission_nonce_valid,
             check: "octet_length(proof_nonce) >= 16 AND octet_length(proof_nonce) <= 64"
           )
    create constraint(:scanner_admissions, :scanner_proof_signature_valid,
             check: "octet_length(proof_signature) = 64"
           )
    create constraint(:scanner_admissions, :scanner_request_signature_valid,
             check: "octet_length(request_nonce) >= 16 AND octet_length(request_nonce) <= 64 AND octet_length(request_signature) = 64"
           )

    create table(:ticket_credential_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :ticket_id, references(:tickets, type: :binary_id, on_delete: :restrict), null: false
      add :event_type, :string, null: false
      add :credential_epoch, :integer, null: false
      add :public_key_fingerprint, :string
      add :actor_user_id, references(:users, on_delete: :nilify_all)
      add :metadata, :map, null: false, default: %{}
      add :occurred_at, :utc_datetime, null: false
      timestamps(updated_at: false)
    end

    create unique_index(:ticket_credential_events, [:ticket_id, :credential_epoch, :event_type])
    create index(:ticket_credential_events, [:ticket_id, :occurred_at])
    create constraint(:ticket_credential_events, :ticket_credential_event_type_valid,
             check: "event_type IN ('bound', 'rebound', 'revoked', 'recovered')"
           )
  end

  def down do
    drop table(:ticket_credential_events)
    drop table(:scanner_admissions)
    drop table(:event_manifests)
    drop table(:scanner_devices)
    drop constraint(:tickets, :ticket_v2_credential_complete)
    drop constraint(:tickets, :ticket_credential_version_valid)
    execute "DROP TRIGGER IF EXISTS ticket_credential_epoch_guard ON tickets"
    execute "DROP FUNCTION IF EXISTS dunda_ticket_credential_epoch_guard()"
    alter table(:tickets) do
      remove :credential_epoch
      remove :credential_bound_at
      remove :credential_valid_until
      remove :credential_valid_from
      remove :credential_public_key
      remove :credential_version
    end
  end
end
