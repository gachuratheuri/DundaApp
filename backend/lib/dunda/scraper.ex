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
    * `{:error, changeset}` on validation failure

  The Bloom filter is advisory only. It is deliberately observed but never
  used as a write gate: a false positive must still reach PostgreSQL's
  authoritative `ON CONFLICT` upsert.
  """
  @spec upsert_event(map()) ::
          {:ok, :inserted | :updated, Event.t()} | {:error, Ecto.Changeset.t()}
  def upsert_event(%{source: source, external_id: external_id} = attrs) do
    dedup_key = "#{source}:#{external_id}"

    _ = Dedup.new?(dedup_key)
    do_upsert(attrs)
  end

  defp do_upsert(attrs) do
    attrs = Map.put_new(attrs, :source_last_seen_at, DateTime.utc_now() |> DateTime.truncate(:second))
    attrs = Map.put_new(attrs, :source_payload_hash, payload_hash(attrs))
    changeset = Event.ingest_changeset(%Event{}, attrs)

    insert_opts = [
      on_conflict: {:replace, [:name, :venue, :starts_at, :price_cents, :capacity, :organisation_id, :source_url, :source_last_seen_at, :source_payload_hash, :updated_at]},
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

  defp payload_hash(attrs) do
    attrs
    |> Map.drop([:source_last_seen_at, :source_payload_hash])
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  # Best-effort: seed the Redis inventory key for a brand-new event so the
  # catalogue shows live remaining capacity. Never fatal.
  defp seed_inventory(%Event{id: id, capacity: capacity}) do
    Redix.command(:redix, ["SET", "inventory:#{id}", to_string(capacity), "NX"])
  rescue
    _ -> :ok
  end
end
