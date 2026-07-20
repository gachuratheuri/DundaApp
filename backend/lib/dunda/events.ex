defmodule Dunda.Events do
  @moduledoc """
  Read-side context for event discovery. Event metadata is read from the
  replica; live remaining inventory is read from Redis (authoritative) with a
  fallback to capacity when no inventory key has been seeded yet. Events carry
  their ticket tiers, each annotated with a live per-tier `remaining`.
  """
  import Ecto.Query, only: [from: 2]

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
        where: e.status == "published" and e.starts_at >= ^from_time and e.starts_at < ^until_time,
        order_by: [asc: e.starts_at, asc: e.id],
        limit: ^(limit + 1),
        preload: [:ticket_tiers]

    query = query |> apply_public_filter(:category, Keyword.get(opts, :category)) |> apply_public_filter(:city, Keyword.get(opts, :city)) |> apply_cursor(cursor)
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
    case ReadRepo.one(from e in Event, where: e.id == ^id and e.status == "published" and e.starts_at >= ^now and e.starts_at < ^until_time) do
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
  defp apply_cursor(query, {starts_at, id}), do: from e in query, where: e.starts_at > ^starts_at or (e.starts_at == ^starts_at and e.id > ^id)

  defp apply_public_filter(query, _field, nil), do: query
  defp apply_public_filter(query, _field, ""), do: query
  defp apply_public_filter(query, :category, value), do: from e in query, where: e.category == ^value
  defp apply_public_filter(query, :city, value), do: from e in query, where: e.city == ^value

  @doc "Create a new event manually with safe Redis inventory seeding."
  @spec create_event(map()) :: {:ok, Event.t()} | {:error, any()}
  def create_event(attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:event, Event.changeset(%Event{}, attrs))
    |> Ecto.Multi.run(:inventory, fn _repo, %{event: event} ->
      seed_inventory(event)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{event: event}} ->
        {:ok, event}

      {:error, _failed_operation, failed_value, _changes_so_far} ->
        {:error, failed_value}
    end
  end

  @doc "Update an existing event."
  @spec update_event(Event.t(), map()) :: {:ok, Event.t()} | {:error, Ecto.Changeset.t()}
  def update_event(%Event{} = event, attrs) do
    event
    |> Event.changeset(attrs)
    |> Repo.update()
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

  defp seed_inventory(%Event{id: id, capacity: capacity}) do
    key = Inventory.inventory_key(Inventory.event_pool(id))

    case Redix.command(:redix, ["SET", key, to_string(capacity), "NX"]) do
      {:ok, _} -> {:ok, :seeded}
      {:error, reason} -> {:error, reason}
    end
  rescue
    e -> {:error, e}
  end
end
