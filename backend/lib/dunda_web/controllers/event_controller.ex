defmodule DundaWeb.EventController do
  use DundaWeb, :controller

  alias Dunda.Events

  def index(conn, _params) do
    render(conn, :index, events: Events.list_events())
  end

  def show(conn, %{"id" => id}) do
    case Events.get_event(id) do
      nil -> {:error, :not_found}
      event -> render(conn, :show, event: event)
    end
  end
end
