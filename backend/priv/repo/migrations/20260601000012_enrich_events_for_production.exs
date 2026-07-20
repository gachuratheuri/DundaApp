defmodule Dunda.Repo.Migrations.EnrichEventsForProduction do
  @moduledoc """
  Promotes the reference `events` table to the production catalogue model the
  UX/UI map requires (DiscoverScreen + EventDetailScreen + Organiser portal):
  rich descriptive metadata, a cover image, a category for the Discover filter
  rail, a publish lifecycle (`status`), an end time, geo coordinates for the
  "Near You Tonight" rail, and a stable public `slug`.

  All columns are nullable or carry a default so the migration is safe to run
  against existing rows. Integrity is enforced at the database with CHECK
  constraints (defence in depth alongside the changeset validations).
  """
  use Ecto.Migration

  def change do
    alter table(:events) do
      add :description, :text
      add :cover_image_url, :string
      # Discover filter rail (All, Festival, Club Night, Afrobeats, Jazz, ...).
      add :category, :string
      add :ends_at, :utc_datetime
      # Publish lifecycle: draft -> published -> cancelled / completed.
      add :status, :string, null: false, default: "published"
      add :city, :string, null: false, default: "Nairobi"
      add :latitude, :float
      add :longitude, :float
      # Public-facing stable identifier (deep links / SEO landing).
      add :slug, :string
      add :currency, :string, null: false, default: "KES"
      add :age_restriction, :integer
      add :published_at, :utc_datetime
    end

    # Discover feed reads published events by start time; portal reads per-org.
    create index(:events, [:status])
    create index(:events, [:category])
    create index(:events, [:status, :starts_at])
    create index(:events, [:organisation_id, :status])

    create unique_index(:events, [:slug], where: "slug IS NOT NULL")

    create constraint(:events, :events_price_cents_non_negative, check: "price_cents >= 0")
    create constraint(:events, :events_capacity_positive, check: "capacity > 0")

    create constraint(:events, :events_status_valid,
             check: "status IN ('draft', 'published', 'cancelled', 'completed')"
           )

    create constraint(:events, :events_ends_after_start,
             check: "ends_at IS NULL OR ends_at >= starts_at"
           )
  end
end
