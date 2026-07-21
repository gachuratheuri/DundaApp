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

    case Repo.get(Ticket, ticket_id) do
      nil -> conn |> put_status(:not_found) |> json(%{error: %{code: "ticket_not_found"}})
      ticket -> create_listing(conn, ticket, user.id, price)
    end
  end

  def create(conn, _params),
    do:
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: %{code: "listing_parameters_required"}})

  defp create_listing(conn, ticket, user_id, price) do
    case Market.list_ticket(ticket, user_id, price) do
      {:ok, listing} ->
        render(conn, :show, listing: listing)

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> put_view(json: DundaWeb.ErrorJSON)
        |> render(:"422", message: to_string(reason))
    end
  end

  @doc "Creates a durable resale payment intent; no ticket transfer occurs here."
  def intent(conn, %{"id" => listing_id, "idempotency_key" => key} = params) do
    user = conn.assigns.current_user

    with {:ok, order} <-
           Market.create_resale_payment_intent(listing_id, user.id, key, params["phone"]),
         {:ok, submitted} <- Dunda.Billing.submit_order_intent(order) do
      json(conn, %{
        payment_intent_id: submitted.id,
        status: submitted.status,
        redirect_url: submitted.redirect_url
      })
    else
      {:error, :phase_0_containment} ->
        conn |> put_status(:service_unavailable) |> json(%{error: %{code: "phase_0_containment"}})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: %{code: to_string(reason)}})
    end
  end

  def intent(conn, _params),
    do:
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: %{code: "idempotency_key_required"}})
end
