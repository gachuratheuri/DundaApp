defmodule Dunda.Repo.Migrations.Phase8ScraperCatalogueIntegrity do
  use Ecto.Migration

  def up do
    alter table(:events) do
      add :source_url, :string
      add :source_last_seen_at, :utc_datetime
      add :source_payload_hash, :string
    end

    create index(:events, [:source, :source_last_seen_at])
    create constraint(:events, :events_source_hash_valid,
             check: "source_payload_hash IS NULL OR source_payload_hash ~ '^[0-9a-f]{64}$'"
           )

    create table(:scrape_source_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :organisation_id, references(:organisations, on_delete: :nilify_all)
      add :source, :string, null: false
      add :target, :string
      add :status, :string, null: false
      add :started_at, :utc_datetime, null: false
      add :finished_at, :utc_datetime
      add :fetched_count, :integer, null: false, default: 0
      add :parsed_count, :integer, null: false, default: 0
      add :inserted_count, :integer, null: false, default: 0
      add :updated_count, :integer, null: false, default: 0
      add :rejected_count, :integer, null: false, default: 0
      add :schema_drift, :boolean, null: false, default: false
      add :response_hash, :string
      add :error_code, :string
      add :metadata, :map, null: false, default: %{}
      timestamps(updated_at: false)
    end

    create index(:scrape_source_runs, [:organisation_id, :source, :started_at])
    create index(:scrape_source_runs, [:status, :finished_at])
    create constraint(:scrape_source_runs, :scrape_source_run_status_valid,
             check: "status IN ('started', 'succeeded', 'failed', 'schema_drift', 'cancelled')"
           )
    create constraint(:scrape_source_runs, :scrape_source_run_counts_valid,
             check: "fetched_count >= 0 AND parsed_count >= 0 AND inserted_count >= 0 AND updated_count >= 0 AND rejected_count >= 0"
           )
    create constraint(:scrape_source_runs, :scrape_source_run_hash_valid,
             check: "response_hash IS NULL OR response_hash ~ '^[0-9a-f]{64}$'"
           )
  end

  def down do
    drop table(:scrape_source_runs)
    drop constraint(:events, :events_source_hash_valid)
    alter table(:events) do
      remove :source_payload_hash
      remove :source_last_seen_at
      remove :source_url
    end
  end
end
