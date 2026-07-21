defmodule Dunda.Scraper.SourceRun do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "scrape_source_runs" do
    field :source, :string
    field :target, :string
    field :status, :string
    field :started_at, :utc_datetime
    field :finished_at, :utc_datetime
    field :fetched_count, :integer, default: 0
    field :parsed_count, :integer, default: 0
    field :inserted_count, :integer, default: 0
    field :updated_count, :integer, default: 0
    field :rejected_count, :integer, default: 0
    field :schema_drift, :boolean, default: false
    field :response_hash, :string
    field :error_code, :string
    field :metadata, :map, default: %{}
    belongs_to :organisation, Dunda.Organisations.Organisation
    timestamps(updated_at: false)
  end

  def changeset(run, attrs) do
    run
    |> cast(attrs, [
      :organisation_id,
      :source,
      :target,
      :status,
      :started_at,
      :finished_at,
      :fetched_count,
      :parsed_count,
      :inserted_count,
      :updated_count,
      :rejected_count,
      :schema_drift,
      :response_hash,
      :error_code,
      :metadata
    ])
    |> validate_required([:source, :status, :started_at, :metadata])
    |> validate_inclusion(:status, ~w(started succeeded failed schema_drift cancelled))
    |> validate_number(:fetched_count, greater_than_or_equal_to: 0)
    |> validate_number(:parsed_count, greater_than_or_equal_to: 0)
    |> validate_number(:inserted_count, greater_than_or_equal_to: 0)
    |> validate_number(:updated_count, greater_than_or_equal_to: 0)
    |> validate_number(:rejected_count, greater_than_or_equal_to: 0)
    |> validate_format(:response_hash, ~r/^[0-9a-f]{64}$/)
    |> assoc_constraint(:organisation)
  end
end
