defmodule Dunda.Events.Event do
  @moduledoc """
  A published live event. For this reference implementation each event maps to a
  single ticket tier whose `ticket_tier_id` equals the event id, so live
  inventory lives at the Redis key `inventory:<id>`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "events" do
    field :name, :string
    field :venue, :string
    field :starts_at, :utc_datetime
    field :price_cents, :integer
    field :capacity, :integer

    # Provenance for scraped events (nil for manually-seeded events).
    field :source, :string
    field :external_id, :string

    # Populated from Redis at read time (see `Dunda.Events`); not persisted.
    field :remaining, :integer, virtual: true

    belongs_to :organisation, Dunda.Organisations.Organisation

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:name, :venue, :starts_at, :price_cents, :capacity, :organisation_id])
    |> validate_required([:name, :venue, :starts_at, :price_cents, :capacity])
    |> validate_number(:price_cents, greater_than_or_equal_to: 0)
    |> validate_number(:capacity, greater_than: 0)
  end

  @doc """
  Changeset for events arriving from the scraper. Requires `:source` and
  `:external_id` so the partial unique index can drive an idempotent upsert.
  """
  @spec ingest_changeset(t(), map()) :: Ecto.Changeset.t()
  def ingest_changeset(event, attrs) do
    event
    |> cast(attrs, [
      :name,
      :venue,
      :starts_at,
      :price_cents,
      :capacity,
      :source,
      :external_id,
      :organisation_id
    ])
    |> validate_required([:name, :venue, :starts_at, :capacity, :source, :external_id])
    |> validate_number(:price_cents, greater_than_or_equal_to: 0)
    |> validate_number(:capacity, greater_than: 0)
    |> unique_constraint([:source, :external_id], name: :events_source_external_id_index)
  end
end
