defmodule Dunda.Events do
  @moduledoc """
  Read-side context for event discovery. Event metadata is read from the
  replica; live remaining inventory is read from Redis (authoritative) with a
  fallback to capacity when no inventory key has been seeded yet.
  """
  import Ecto.Query, only: [from: 2]

  alias Dunda.Events.Event
  alias Dunda.ReadRepo

  @doc "List all events ordered by start time, each annotated with `:remaining`."
  @spec list_events() :: [Event.t()]
  def list_events do
    Event
    |> from(order_by: [asc: :starts_at])
    |> ReadRepo.all()
    |> Enum.map(&annotate_remaining/1)
  end

  @doc "Fetch a single event with `:remaining`, or `nil`."
  @spec get_event(integer() | String.t()) :: Event.t() | nil
  def get_event(id) do
    case ReadRepo.get(Event, id) do
      nil -> nil
      event -> annotate_remaining(event)
    end
  end

  defp annotate_remaining(%Event{} = event) do
    remaining =
      case Redix.command(:redix, ["GET", "inventory:#{event.id}"]) do
        {:ok, nil} -> event.capacity
        {:ok, value} -> String.to_integer(value)
        _ -> event.capacity
      end

    %{event | remaining: remaining}
  rescue
    _ -> %{event | remaining: event.capacity}
  end
end
