defmodule Dunda.Repo.Migrations.AddScraperColumnsToEvents do
  use Ecto.Migration

  def change do
    alter table(:events) do
      # Tenant ownership — set from dispatch metadata when an org triggers a scrape.
      add :organisation_id, references(:organisations, on_delete: :nilify_all)

      # Provenance + dedup identity for scraped events.
      add :source, :string
      add :external_id, :string
    end

    create index(:events, [:organisation_id])

    # Idempotent upsert target: a given (source, external_id) maps to one event.
    # Partial unique index so manually-seeded events (source IS NULL) are unconstrained.
    create unique_index(:events, [:source, :external_id],
             where: "source IS NOT NULL AND external_id IS NOT NULL",
             name: :events_source_external_id_index
           )
  end
end
