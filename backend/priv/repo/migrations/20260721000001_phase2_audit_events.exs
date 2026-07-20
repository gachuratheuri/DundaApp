defmodule Dunda.Repo.Migrations.Phase2AuditEvents do
  use Ecto.Migration

  def up do
    create table(:audit_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :actor_user_id, references(:users, on_delete: :nilify_all)
      add :action, :string, null: false
      add :resource_type, :string
      add :resource_id, :string
      add :metadata, :map, null: false, default: %{}
      add :request_id, :string
      add :occurred_at, :utc_datetime, null: false
      timestamps(updated_at: false)
    end

    create index(:audit_events, [:actor_user_id, :occurred_at])
    create index(:audit_events, [:resource_type, :resource_id, :occurred_at])
    create index(:audit_events, [:occurred_at])
    create index(:audit_events, [:request_id])
    create constraint(:audit_events, :audit_events_action_present, check: "length(trim(action)) >= 3")
    create constraint(:audit_events, :audit_events_metadata_object, check: "jsonb_typeof(metadata) = 'object'")

    execute("""
    CREATE OR REPLACE FUNCTION dunda_reject_audit_mutation() RETURNS trigger AS $$
    BEGIN
      RAISE EXCEPTION 'audit_events are append-only';
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE TRIGGER audit_events_immutable
    BEFORE UPDATE OR DELETE ON audit_events
    FOR EACH ROW EXECUTE FUNCTION dunda_reject_audit_mutation();
    """)
  end

  def down do
    execute("DROP TRIGGER IF EXISTS audit_events_immutable ON audit_events")
    execute("DROP FUNCTION IF EXISTS dunda_reject_audit_mutation()")
    drop table(:audit_events)
  end
end
