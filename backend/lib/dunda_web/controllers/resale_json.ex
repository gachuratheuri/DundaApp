defmodule DundaWeb.ResaleJSON do
  @moduledoc "JSON view for resale listings."

  def index(%{listings: listings}) do
    %{data: Enum.map(listings, &data/1)}
  end

  def show(%{listing: listing}) do
    %{data: data(listing)}
  end

  defp data(listing) do
    %{
      id: listing.id,
      ticket_id: listing.ticket_id,
      seller_id: listing.seller_id,
      asking_price_cents: listing.asking_price_cents,
      face_value_cents: listing.face_value_cents,
      status: listing.status,
      ticket_details: ticket_details(listing)
    }
  end

  defp ticket_details(listing) do
    if Ecto.assoc_loaded?(listing.ticket) and not is_nil(listing.ticket) do
      event_name =
        if Ecto.assoc_loaded?(listing.ticket.event) and not is_nil(listing.ticket.event) do
          listing.ticket.event.name
        else
          nil
        end

      %{
        tier: listing.ticket.tier_label,
        event_name: event_name
      }
    else
      nil
    end
  end
end
