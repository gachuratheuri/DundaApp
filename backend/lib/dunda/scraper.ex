defmodule Dunda.Scraper do
  @moduledoc """
  Write-side context for the scraper pipeline: dedup + idempotent upsert of
  canonical events into the catalogue.

  `IngestWorker` is the only caller — this module is the seam where a normalised
  event becomes a durable, tenant-owned `events` row.
  """
  import Ecto.Query, only: [from: 2]
  require Logger

  alias Dunda.Checkout.InventoryPool
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
    attrs =
      Map.put_new(attrs, :source_last_seen_at, DateTime.utc_now() |> DateTime.truncate(:second))

    attrs = Map.put_new(attrs, :source_payload_hash, payload_hash(attrs))
    changeset = Event.ingest_changeset(%Event{}, attrs)

    insert_opts = [
      on_conflict:
        {:replace,
         [
           :name,
           :venue,
           :starts_at,
           :price_cents,
           :capacity,
           :organisation_id,
           :source_url,
           :source_last_seen_at,
           :source_payload_hash,
           :updated_at
         ]},
      # Partial unique index target — must mirror the migration's WHERE clause.
      conflict_target:
        {:unsafe_fragment,
         "(source, external_id) WHERE source IS NOT NULL AND external_id IS NOT NULL"},
      returning: true
    ]

    result =
      Repo.transaction(fn ->
        case Repo.insert(changeset, insert_opts) do
          {:ok, event} ->
            pool = upsert_inventory_pool!(event)
            enqueue_inventory_projection!(pool)
            outcome = if event.inserted_at == event.updated_at, do: :inserted, else: :updated
            {outcome, event}

          {:error, failed_changeset} ->
            Repo.rollback(failed_changeset)
        end
      end)

    case result do
      {:ok, {outcome, event}} ->
        {:ok, outcome, event}

      {:error, reason} ->
        {:error, reason}
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

  defp upsert_inventory_pool!(%Event{} = event) do
    case Repo.one(
           from p in InventoryPool,
             where: p.event_id == ^event.id and is_nil(p.ticket_tier_id),
             lock: "FOR UPDATE"
         ) do
      nil ->
        %InventoryPool{}
        |> InventoryPool.changeset(%{
          pool_key: "event:#{event.id}",
          event_id: event.id,
          capacity: event.capacity,
          reserved: 0,
          sold: 0,
          version: 1
        })
        |> Repo.insert!()

      %InventoryPool{} = pool when event.capacity >= pool.reserved + pool.sold ->
        pool
        |> InventoryPool.changeset(%{capacity: event.capacity, version: pool.version + 1})
        |> Repo.update!()

      %InventoryPool{} ->
        Repo.rollback(:capacity_below_committed_inventory)
    end
  end

  defp enqueue_inventory_projection!(pool) do
    %Dunda.Checkout.OutboxEvent{}
    |> Dunda.Checkout.OutboxEvent.changeset(%{
      event_key: "inventory-pool:#{pool.id}:v#{pool.version}",
      event_type: "inventory_projection_changed",
      aggregate_type: "inventory_pool",
      aggregate_id: pool.id,
      payload: %{inventory_pool_id: pool.id, version: pool.version},
      status: "pending",
      available_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.insert!(on_conflict: :nothing, conflict_target: :event_key)
  end
end
