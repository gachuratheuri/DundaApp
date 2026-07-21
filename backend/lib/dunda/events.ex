defmodule Dunda.Events do
  @moduledoc """
  Read-side context for event discovery. Event metadata is read from the
  replica; discovery availability may use the rebuildable Redis projection and
  falls back to PostgreSQL truth when that projection is absent. Events carry
  their ticket tiers, each annotated with a live per-tier `remaining`.
  """
  import Ecto.Query, only: [from: 2]

  alias Dunda.Checkout.InventoryPool
  alias Dunda.Events.Event
  alias Dunda.Inventory
  alias Dunda.ReadRepo
  alias Dunda.Repo
  alias Dunda.Ticketing.TicketTier

  @doc "Legacy list API; returns the first public page."
  def list_events, do: list_public_events() |> Map.fetch!(:events)

  @doc "Lists published upcoming events using a stable, opaque cursor."
  def list_public_events(opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    from_time = Keyword.get(opts, :from, now)
    until_time = Keyword.get(opts, :until, DateTime.add(from_time, 365, :day))
    limit = opts |> Keyword.get(:limit, 20) |> normalize_limit()
    cursor = decode_cursor(Keyword.get(opts, :after))

    query =
      from e in Event,
        where:
          e.status == "published" and e.starts_at >= ^from_time and e.starts_at < ^until_time,
        order_by: [asc: e.starts_at, asc: e.id],
        limit: ^(limit + 1),
        preload: [:ticket_tiers]

    query =
      query
      |> apply_public_filter(:category, Keyword.get(opts, :category))
      |> apply_public_filter(:city, Keyword.get(opts, :city))
      |> apply_cursor(cursor)

    events = query |> ReadRepo.all() |> Enum.map(&annotate_remaining/1)
    {page, rest} = Enum.split(events, limit)
    %{events: page, next_cursor: if(rest == [], do: nil, else: encode_cursor(List.last(page)))}
  end

  @doc "Lists events limited to the supplied organisation tenant ids."
  @spec list_events_for_organisations([integer()]) :: [Event.t()]
  def list_events_for_organisations(organisation_ids) when is_list(organisation_ids) do
    from(e in Event,
      # Tenant reads are not public discovery reads: organisers must be able
      # to manage drafts, scheduled events, cancellations, and archived
      # records belonging to their own organisations.  Public visibility is
      # enforced exclusively by `list_events/0` and `get_public_event/1`.
      where: e.organisation_id in ^organisation_ids,
      order_by: [asc: :starts_at],
      preload: [:ticket_tiers]
    )
    |> Repo.all()
    |> Enum.map(&annotate_remaining/1)
  end

  @doc "Fetch a single event with `:remaining`, or `nil`."
  @spec get_event(integer() | String.t()) :: Event.t() | nil
  def get_event(id) do
    case ReadRepo.get(Event, id) do
      nil -> nil
      event -> event |> Repo.preload(:ticket_tiers) |> annotate_remaining()
    end
  end

  @doc "Fetches an event only when it belongs to one of the supplied tenants."
  @spec get_event_for_organisations(integer() | String.t(), [integer()]) :: Event.t() | nil
  def get_event_for_organisations(id, organisation_ids) when is_list(organisation_ids) do
    case Repo.one(from e in Event, where: e.id == ^id and e.organisation_id in ^organisation_ids) do
      nil -> nil
      event -> event |> ReadRepo.preload(:ticket_tiers) |> annotate_remaining()
    end
  end

  @doc "Fetches an event only when it is publicly published."
  @spec get_public_event(integer() | String.t()) :: Event.t() | nil
  def get_public_event(id, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    until_time = Keyword.get(opts, :until, DateTime.add(now, 365, :day))

    case ReadRepo.one(
           from e in Event,
             where:
               e.id == ^id and e.status == "published" and e.starts_at >= ^now and
                 e.starts_at < ^until_time
         ) do
      nil -> nil
      event -> event |> ReadRepo.preload(:ticket_tiers) |> annotate_remaining()
    end
  end

  defp normalize_limit(limit) when is_integer(limit), do: min(max(limit, 1), 100)
  defp normalize_limit(_), do: 20

  defp encode_cursor(%Event{starts_at: starts_at, id: id}) do
    Base.url_encode64("#{DateTime.to_iso8601(starts_at)}|#{id}", padding: false)
  end

  defp decode_cursor(nil), do: nil

  defp decode_cursor(cursor) when is_binary(cursor) do
    with {:ok, raw} <- Base.url_decode64(cursor, padding: false),
         [starts_at, id] <- String.split(raw, "|", parts: 2),
         {:ok, datetime, _} <- DateTime.from_iso8601(starts_at),
         {id, ""} <- Integer.parse(id) do
      {datetime, id}
    else
      _ -> nil
    end
  end

  defp decode_cursor(_), do: nil

  defp apply_cursor(query, nil), do: query

  defp apply_cursor(query, {starts_at, id}),
    do:
      from(e in query,
        where: e.starts_at > ^starts_at or (e.starts_at == ^starts_at and e.id > ^id)
      )

  defp apply_public_filter(query, _field, nil), do: query
  defp apply_public_filter(query, _field, ""), do: query

  defp apply_public_filter(query, :category, value),
    do: from(e in query, where: e.category == ^value)

  defp apply_public_filter(query, :city, value), do: from(e in query, where: e.city == ^value)

  @doc """
  Creates a new event, its authoritative PostgreSQL inventory pool, and a
  durable outbox intent for the disposable Redis projection.

  Before this, no application code path ever created a
  `Dunda.Checkout.InventoryPool` row for an event — only a one-time
  migration backfill did, for events that already existed when Phase 3-5
  shipped (`priv/repo/migrations/20260725000001_phase3_5_checkout_authority.exs`).
  Every event created since then had no pool, so
  `Dunda.Checkout.create_payment_intent/2` failed for it with
  `{:error, :inventory_pool_not_found}` — the reservation path was
  non-functional for any new event. This is a Critical fix; see
  `docs/phase_12_verification_observability_rollout.md`, finding F0.

  No live code path creates a `Dunda.Ticketing.TicketTier` today (confirmed:
  no controller, LiveView, or context function does — `event_editor_live.ex`
  only *simulates* a tiers list in its form state and collapses it into this
  event's own flat `capacity`/`price_cents` before calling this function),
  so only the untiered pool needs provisioning here. If/when tier creation
  is implemented, it must provision its own per-tier pool the same way,
  mirroring the migration's `'tier:' || tier.id` pool-key convention.
  """
  @spec create_event(map()) :: {:ok, Event.t()} | {:error, any()}
  def create_event(attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:event, Event.changeset(%Event{}, attrs))
    |> Ecto.Multi.insert(:inventory_pool, fn %{event: event} ->
      InventoryPool.changeset(%InventoryPool{}, %{
        pool_key: "event:#{event.id}",
        capacity: event.capacity,
        reserved: 0,
        sold: 0,
        version: 1,
        event_id: event.id
      })
    end)
    |> Ecto.Multi.insert(:inventory_projection_intent, fn %{inventory_pool: pool} ->
      Dunda.Checkout.OutboxEvent.changeset(%Dunda.Checkout.OutboxEvent{}, %{
        event_key: "inventory-pool:#{pool.id}:v#{pool.version}",
        event_type: "inventory_projection_changed",
        aggregate_type: "inventory_pool",
        aggregate_id: pool.id,
        payload: %{inventory_pool_id: pool.id, version: pool.version},
        status: "pending",
        available_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{event: event}} ->
        {:ok, event}

      {:error, _failed_operation, failed_value, _changes_so_far} ->
        {:error, failed_value}
    end
  end

  @doc """
  Update an existing event. When `capacity` changes, the authoritative
  untiered inventory pool's capacity is kept in sync in the same
  transaction — reducing capacity below already-committed inventory
  (`reserved + sold`) is rejected (`{:error, :capacity_below_committed_inventory}`)
  rather than silently dropped or left to crash on the database's
  `inventory_pool_counts_valid` CHECK constraint.
  """
  @spec update_event(Event.t(), map()) ::
          {:ok, Event.t()} | {:error, Ecto.Changeset.t() | :capacity_below_committed_inventory}
  def update_event(%Event{} = event, attrs) do
    Repo.transaction(fn ->
      case event |> Event.changeset(attrs) |> Repo.update() do
        {:ok, updated_event} ->
          case sync_inventory_pool_capacity(updated_event) do
            :ok -> updated_event
            {:error, reason} -> Repo.rollback(reason)
          end

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  defp sync_inventory_pool_capacity(%Event{id: id, capacity: capacity}) do
    {count, _} =
      Repo.update_all(
        from(p in InventoryPool,
          where:
            p.event_id == ^id and is_nil(p.ticket_tier_id) and p.reserved + p.sold <= ^capacity
        ),
        set: [capacity: capacity],
        inc: [version: 1]
      )

    cond do
      count == 1 ->
        pool = Repo.get_by!(InventoryPool, event_id: id, ticket_tier_id: nil)
        enqueue_inventory_projection!(pool)
        :ok

      # No untiered pool exists for this event (e.g. a pre-fix event that
      # hasn't been backfilled, or a tiered event) — nothing to keep in
      # sync; not this function's concern.
      not Repo.exists?(
        from(p in InventoryPool, where: p.event_id == ^id and is_nil(p.ticket_tier_id))
      ) ->
        :ok

      true ->
        {:error, :capacity_below_committed_inventory}
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

  defp annotate_remaining(%Event{} = event) do
    tiers =
      event.ticket_tiers
      |> tiers_or_empty()
      |> Enum.sort_by(&{&1.sort_order, &1.price_cents})
      |> Enum.map(&annotate_tier/1)

    remaining =
      case tiers do
        [] -> Inventory.remaining(Inventory.event_pool(event.id), event.capacity)
        tiers -> tiers |> Enum.map(& &1.remaining) |> Enum.sum()
      end

    %{event | ticket_tiers: tiers, remaining: remaining}
  rescue
    _ -> %{event | remaining: event.capacity}
  end

  defp annotate_tier(%TicketTier{} = tier) do
    %{tier | remaining: Inventory.remaining(Inventory.tier_pool(tier.id), tier.capacity)}
  end

  # Tolerate callers that built an %Event{} without preloading tiers.
  defp tiers_or_empty(%Ecto.Association.NotLoaded{}), do: []
  defp tiers_or_empty(tiers) when is_list(tiers), do: tiers
end
