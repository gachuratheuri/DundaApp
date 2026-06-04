defmodule DundaWeb.TicketJSON do
  @moduledoc "Serialises tickets into the shape consumed by the app's `DundaTicket`."

  def index(%{tickets: tickets}), do: %{data: Enum.map(tickets, &data/1)}

  defp data(ticket) do
    %{
      id: ticket.id,
      eventName: ticket.event.name,
      venue: ticket.event.venue,
      date: format_date(ticket.event.starts_at),
      tier: ticket.tier_label,
      jwt: ticket.jwt
    }
  end

  defp format_date(%DateTime{} = utc) do
    local = DateTime.add(utc, 3 * 3600, :second)
    Calendar.strftime(local, "%a %d %b · %H:%M") |> String.upcase()
  end
end
