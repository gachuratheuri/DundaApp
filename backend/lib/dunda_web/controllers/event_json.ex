defmodule DundaWeb.EventJSON do
  @moduledoc "Serialises events into the shape consumed by the app's `DundaEvent`."

  alias Dunda.Events.Event

  def index(%{events: events}), do: %{data: Enum.map(events, &data/1)}
  def show(%{event: event}), do: %{data: data(event)}

  defp data(%Event{} = event) do
    %{
      id: to_string(event.id),
      name: event.name,
      venue: event.venue,
      date: format_date(event.starts_at),
      price: div(event.price_cents, 100),
      remaining: event.remaining || event.capacity,
      capacity: event.capacity
    }
  end

  # "FRI 12 JUN · 22:00" in Nairobi local time (UTC+3, no DST).
  defp format_date(%DateTime{} = utc) do
    local = DateTime.add(utc, 3 * 3600, :second)
    Calendar.strftime(local, "%a %d %b · %H:%M") |> String.upcase()
  end
end
