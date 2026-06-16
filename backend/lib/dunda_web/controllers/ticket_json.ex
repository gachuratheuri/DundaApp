defmodule DundaWeb.TicketJSON do
  @moduledoc "Serialises tickets into the shape consumed by the app's `DundaTicket`."

  def index(%{tickets: tickets}), do: %{data: Enum.map(tickets, &data/1)}

  defp data(ticket) do
    # Frontend expects either tier or tier_label, we'll return both to be safe
    # Also calculate if it's VIP based on tier_label
    is_vip = String.contains?(String.upcase(ticket.tier_label || ""), "VIP")
    
    # We don't have holder on ticket, so we'll stub it with user's email or "Guest" for now if not preloaded
    holder = "David M." # Hardcoded for now unless we preload User
    
    # Map ticket.status to frontend status ('active' | 'pending' | 'attended' | 'resale_pending')
    status = 
      cond do
        ticket.status == "scanned" -> "attended"
        ticket.status == "valid" -> "active"
        true -> "pending"
      end

    %{
      id: ticket.id,
      event_id: ticket.event.id,
      event_name: ticket.event.name,
      venue: ticket.event.venue,
      date_label: format_date(ticket.event.starts_at),
      tier_label: ticket.tier_label,
      tier: ticket.tier_label,
      is_vip: is_vip,
      holder: holder,
      jwt: ticket.jwt,
      is_scanned: ticket.status == "scanned",
      status: status,
      resale_status: "none"
    }
  end

  defp format_date(%DateTime{} = utc) do
    local = DateTime.add(utc, 3 * 3600, :second)
    Calendar.strftime(local, "%a %d %b · %H:%M") |> String.upcase()
  end
end
