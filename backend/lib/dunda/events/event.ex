defmodule Dunda.Events.Event do
  @moduledoc """
  A published live event.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "events" do
    field :name, :string
    field :venue, :string
    field :starts_at, :utc_datetime
    field :ends_at, :utc_datetime
    field :price_cents, :integer
    field :capacity, :integer

    field :description, :string
    field :cover_image_url, :string
    field :category, :string
    field :status, :string, default: "published"
    field :city, :string, default: "Nairobi"
    field :latitude, :float
    field :longitude, :float
    field :slug, :string
    field :currency, :string, default: "KES"
    field :age_restriction, :integer
    field :published_at, :utc_datetime

    # Provenance for scraped events (nil for manually-seeded events).
    field :source, :string
    field :external_id, :string
    field :source_url, :string
    field :source_last_seen_at, :utc_datetime
    field :source_payload_hash, :string

    # Populated from Redis at read time (see `Dunda.Events`); not persisted.
    field :remaining, :integer, virtual: true

    belongs_to :organisation, Dunda.Organisations.Organisation

    has_many :ticket_tiers, Dunda.Ticketing.TicketTier
    has_many :extras, Dunda.Events.Extra
    has_many :waitlist_entries, Dunda.Events.WaitlistEntry
    has_many :reviews, Dunda.Events.Review
    has_many :favorites, Dunda.Events.EventFavorite
    has_many :ticket_scans, Dunda.Ticketing.TicketScan

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :name, :venue, :starts_at, :ends_at, :price_cents, :capacity, :organisation_id,
      :description, :cover_image_url, :category, :status, :city, :latitude, :longitude,
      :slug, :currency, :age_restriction, :published_at, :source_url, :source_last_seen_at,
      :source_payload_hash
    ])
    |> validate_required([:name, :venue, :starts_at, :price_cents, :capacity, :status, :city, :currency])
    |> validate_number(:price_cents, greater_than_or_equal_to: 0)
    |> validate_number(:capacity, greater_than: 0)
    |> validate_inclusion(:status, ["draft", "published", "cancelled", "completed"])
  end

  @doc """
  Changeset for events arriving from the scraper. Requires `:source` and
  `:external_id` so the partial unique index can drive an idempotent upsert.
  """
  @spec ingest_changeset(t(), map()) :: Ecto.Changeset.t()
  def ingest_changeset(event, attrs) do
    event
    |> cast(attrs, [
      :name, :venue, :starts_at, :price_cents, :capacity, :source, :external_id, :organisation_id,
      :description, :cover_image_url, :category, :status, :city, :latitude, :longitude, :slug,
      :source_url, :source_last_seen_at, :source_payload_hash
    ])
    |> validate_required([:name, :venue, :starts_at, :capacity, :source, :external_id])
    |> validate_number(:price_cents, greater_than_or_equal_to: 0)
    |> validate_number(:capacity, greater_than: 0)
    |> validate_format(:source_payload_hash, ~r/^[0-9a-f]{64}$/)
    |> unique_constraint([:source, :external_id], name: :events_source_external_id_index)
  end
end
