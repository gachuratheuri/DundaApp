defmodule Dunda.Repo.Migrations.CreateOrganisations do
  use Ecto.Migration

  def change do
    create table(:organisations) do
      add :name, :string, null: false
      add :slug, :string, null: false

      add :facebook_page_id, :string
      add :instagram_account_id, :string
      add :eventbrite_org_id, :string
      add :html_scrape_url, :string

      add :scraper_enabled, :boolean, null: false, default: true
      add :mpesa_phone, :string

      timestamps()
    end

    create unique_index(:organisations, [:slug])
    # Partial index: the dispatcher only ever scans enabled orgs.
    create index(:organisations, [:scraper_enabled], where: "scraper_enabled = true")
  end
end
