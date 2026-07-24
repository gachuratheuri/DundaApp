defmodule DundaWeb.TicketJSON do
  @moduledoc "Serialises tickets into the shape consumed by the app's `DundaTicket`."

  def index(%{tickets: tickets}), do: %{data: Enum.map(tickets, &data/1)}

  defp data(ticket) do
    is_vip = String.contains?(String.upcase(ticket.tier_label || ""), "VIP")
    holder = ticket.holder_name || "Ticket holder"

    status =
      cond do
        ticket.status == "scanned" -> "attended"
        ticket.status == "valid" -> "active"
        true -> "pending"
      end

    %{
      id: ticket.id,
      event_id: to_string(ticket.event.id),
      event_name: ticket.event.name,
      venue: ticket.event.venue,
      date_label: format_date(ticket.event.starts_at),
      tier_label: ticket.tier_label,
      face_value_cents: ticket.price_cents,
      tier: ticket.tier_label,
      is_vip: is_vip,
      holder: holder,
      jwt: ticket.jwt,
      protocol_version: ticket.credential_version,
      credential_public_key: encode_key(ticket.credential_public_key),
      credential_valid_from: ticket.credential_valid_from,
      credential_valid_until: ticket.credential_valid_until,
      credential_epoch: ticket.credential_epoch,
      credential_status:
        if(ticket.credential_version == 2 and ticket.status in ["valid", "scanned"],
          do: "device_bound",
          else: "legacy_or_revoked"
        ),
      is_scanned: ticket.status == "scanned",
      status: status,
      resale_status: "none"
    }
  end

  defp encode_key(nil), do: nil
  defp encode_key(key), do: Base.url_encode64(key, padding: false)

  defp format_date(%DateTime{} = utc) do
    local = DateTime.add(utc, 3 * 3600, :second)
    Calendar.strftime(local, "%a %d %b · %H:%M") |> String.upcase()
  end
end
