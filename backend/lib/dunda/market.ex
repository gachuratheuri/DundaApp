defmodule Dunda.Market do
  @moduledoc """
  Secondary market context for listing and buying resale tickets.
  """
  import Ecto.Query, only: [from: 2]

  alias Dunda.Repo
  alias Dunda.Market.Listing
  alias Dunda.Ticketing.Ticket
  alias Dunda.Ledger

  @doc """
  Lists a ticket for sale on the secondary market.
  """
  def list_ticket(%Ticket{} = ticket, seller_id, asking_price) do
    if ticket.user_id == seller_id and ticket.status == "valid" do
      %Listing{}
      |> Listing.changeset(%{
        ticket_id: ticket.id,
        seller_id: seller_id,
        asking_price_kes: asking_price,
        status: "active"
      })
      |> Repo.insert()
    else
      {:error, :unauthorized_or_invalid_ticket}
    end
  end

  @doc """
  Gets an active listing.
  """
  def get_active_listing!(id) do
    Repo.get_by!(Listing, id: id, status: "active")
    |> Repo.preload(ticket: :event)
  end

  @doc """
  Lists all active listings.
  """
  def list_active_listings do
    Repo.all(
      from l in Listing,
        where: l.status == "active",
        preload: [ticket: :event]
    )
  end

  @doc """
  Executes a purchase of a resale listing.
  In a real scenario, this coordinates with Billing to ensure the buyer paid.
  Upon successful payment:
  1. Transfer the ticket to the buyer.
  2. Mark the listing as sold.
  3. Credit the seller's wallet via Dunda.Ledger.
  """
  def execute_purchase(%Listing{} = listing, buyer_id) do
    Repo.transaction(fn ->
      # 1. Update listing
      listing =
        listing
        |> Listing.changeset(%{status: "sold"})
        |> Repo.update!()

      # 2. Update ticket ownership
      ticket = Repo.get!(Ticket, listing.ticket_id)
      
      ticket
      |> Ticket.changeset(%{user_id: buyer_id}) # Simplistic transfer, normally invalidates old JWT and mints new one
      |> Repo.update!()

      # 3. Payout seller
      Ledger.record_transfer(%{
        from_account: "system_escrow",
        to_account: "user_wallet_#{listing.seller_id}",
        amount_cents: listing.asking_price_kes,
        reference: "resale_#{listing.id}"
      })

      listing
    end)
  end
end
