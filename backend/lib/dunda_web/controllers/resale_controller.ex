defmodule DundaWeb.ResaleController do
  use DundaWeb, :controller

  alias Dunda.Market
  alias Dunda.Repo
  alias Dunda.Ticketing.Ticket

  @doc """
  GET /api/resale/listings
  """
  def index(conn, _params) do
    listings = Market.list_active_listings()
    render(conn, :index, listings: listings)
  end

  @doc """
  POST /api/resale/listings
  Creates a new listing.
  """
  def create(conn, %{"ticket_id" => ticket_id, "asking_price_kes" => price}) do
    user = conn.assigns.current_user
    ticket = Repo.get!(Ticket, ticket_id)

    case Market.list_ticket(ticket, user.id, price) do
      {:ok, listing} ->
        render(conn, :show, listing: listing)

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> put_view(json: DundaWeb.ErrorJSON)
        |> render(:"422", message: to_string(reason))
    end
  end

  @doc """
  POST /api/resale/listings/:id/buy
  Purchases an active listing.
  """
  def buy(conn, %{"id" => id}) do
    user = conn.assigns.current_user
    listing = Market.get_active_listing!(id)

    case Market.execute_purchase(listing, user.id) do
      {:ok, sold_listing} ->
        render(conn, :show, listing: sold_listing)

      {:error, _reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> put_view(json: DundaWeb.ErrorJSON)
        |> render(:"422", message: "Purchase failed")
    end
  end
end
