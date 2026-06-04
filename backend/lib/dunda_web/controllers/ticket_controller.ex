defmodule DundaWeb.TicketController do
  use DundaWeb, :controller

  alias Dunda.Ticketing

  @doc """
  GET /api/tickets

  Returns the caller's active tickets, loaded from the database.
  """
  def index(conn, _params) do
    user = conn.assigns.current_user
    tickets = Ticketing.list_user_tickets(user.id)
    render(conn, :index, tickets: tickets)
  end
end
