defmodule DundaWeb.EventController do
  use DundaWeb, :controller

  alias Dunda.Events

  def index(conn, params) do
    page = Events.list_public_events(limit: parse_limit(params["limit"]), after: params["after"], category: params["category"], city: params["city"])
    render(conn, :index, events: page.events, meta: %{next_cursor: page.next_cursor, limit: parse_limit(params["limit"])})
  end

  def show(conn, %{"id" => id}) do
    case Events.get_public_event(id) do
      nil -> {:error, :not_found}
      event -> render(conn, :show, event: event)
    end
  end

  defp parse_limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {limit, ""} -> limit
      _ -> 20
    end
  end
  defp parse_limit(_), do: 20
end
