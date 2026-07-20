defmodule DundaWeb.MetricsController do
  use DundaWeb, :controller

  def show(conn, _params) do
    if DundaWeb.InternalAuth.authorized?(conn) do
      json(conn, %{metrics: Dunda.Observability.snapshot()})
    else
      conn
      |> put_status(:not_found)
      |> json(%{error: %{code: "not_found"}})
    end
  end
end
