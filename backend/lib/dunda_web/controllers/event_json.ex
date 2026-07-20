defmodule DundaWeb.EventJSON do
  @moduledoc """
  Serialises events into the shape consumed by the app's `DundaEvent`.

  Field-name caveat: the app's `price_kes` fields are denominated in *cents*
  (it divides by 100 for display), so `price_cents` passes through unchanged.
  """

  alias Dunda.Events.Event

  def index(%{events: events} = assigns) do
    %{data: Enum.map(events, &data/1), meta: Map.get(assigns, :meta, %{next_cursor: nil})}
  end

  def show(%{event: event}), do: %{data: data(event)}

  defp data(%Event{} = event) do
    remaining = event.remaining || event.capacity
    tiers = tiers_data(event.ticket_tiers)

    %{
      id: to_string(event.id),
      name: event.name,
      venue: event.venue,
      starts_at: DateTime.to_iso8601(event.starts_at),
      price_kes: headline_price_cents(tiers, event),
      remaining: remaining,
      sold_out: remaining == 0,
      tier_label: (tiers && hd(tiers).label) || "GENERAL",
      is_vip: false,
      cover_uri: event.cover_image_url,
      genre_tag: event.category,
      description: event.description,
      capacity: event.capacity,
      tiers: tiers
    }
  end

  # `nil` (not `[]`) when the event has no tiers — the app falls back to its
  # single synthetic tier row in that case.
  defp tiers_data(%Ecto.Association.NotLoaded{}), do: nil
  defp tiers_data([]), do: nil

  defp tiers_data(tiers) when is_list(tiers) do
    Enum.map(tiers, fn t ->
      # `remaining` is annotated from Redis by `Dunda.Events`; fall back to
      # capacity for un-annotated structs.
      live_remaining = t.remaining || t.capacity

      %{
        id: to_string(t.id),
        label: String.upcase(t.name),
        price_kes: t.price_cents,
        sold: max(t.capacity - live_remaining, 0),
        total: t.capacity,
        remaining: live_remaining,
        vip: t.is_vip,
        status: t.status,
        max_per_order: t.max_per_order
      }
    end)
  end

  # Headline price: cheapest tier still buyable, else the event-level price.
  defp headline_price_cents(nil, event), do: event.price_cents

  defp headline_price_cents(tiers, event) do
    tiers
    |> Enum.filter(&(&1.status == "on_sale" and &1.remaining > 0))
    |> Enum.map(& &1.price_kes)
    |> Enum.min(fn -> event.price_cents end)
  end
end
