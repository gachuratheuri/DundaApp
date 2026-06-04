defmodule Dunda.Scraper do
  @moduledoc """
  Write-side context for the scraper pipeline: dedup + idempotent upsert of
  canonical events into the catalogue.

  `IngestWorker` is the only caller — this module is the seam where a normalised
  event becomes a durable, tenant-owned `events` row.
  """
  require Logger

  alias Dunda.Events.Event
  alias Dunda.Repo
  alias Dunda.Scraper.Dedup

  @doc """
  Upsert one canonical event map (see `Normaliser`) into the catalogue.

  Returns:
    * `{:ok, :inserted | :updated, %Event{}}`
    * `{:skip, :duplicate}` when the Bloom pre-filter short-circuits
    * `{:error, changeset}` on validation failure
  """
  @spec upsert_event(map()) ::
          {:ok, :inserted | :updated, Event.t()} | {:skip, :duplicate} | {:error, Ecto.Changeset.t()}
  def upsert_event(%{source: source, external_id: external_id} = attrs) do
    dedup_key = "#{source}:#{external_id}"

    if Dedup.new?(dedup_key) do
      do_upsert(attrs)
    else
      {:skip, :duplicate}
    end
  end

  defp do_upsert(attrs) do
    changeset = Event.ingest_changeset(%Event{}, attrs)

    insert_opts = [
      on_conflict: {:replace, [:name, :venue, :starts_at, :price_cents, :capacity, :organisation_id, :updated_at]},
      # Partial unique index target — must mirror the migration's WHERE clause.
      conflict_target:
        {:unsafe_fragment, "(source, external_id) WHERE source IS NOT NULL AND external_id IS NOT NULL"},
      returning: true
    ]

    case Repo.insert(changeset, insert_opts) do
      {:ok, event} ->
        seed_inventory(event)
        outcome = if event.inserted_at == event.updated_at, do: :inserted, else: :updated
        {:ok, outcome, event}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  # Best-effort: seed the Redis inventory key for a brand-new event so the
  # catalogue shows live remaining capacity. Never fatal.
  defp seed_inventory(%Event{id: id, capacity: capacity}) do
    Redix.command(:redix, ["SET", "inventory:#{id}", to_string(capacity), "NX"])
  rescue
    _ -> :ok
  end
end
