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

  @doc "Prometheus text-exposition scrape target — see Dunda.Observability.render_prometheus/0."
  def prometheus(conn, _params) do
    if DundaWeb.InternalAuth.authorized?(conn) do
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(200, Dunda.Observability.render_prometheus())
    else
      conn
      |> put_status(:not_found)
      |> json(%{error: %{code: "not_found"}})
    end
  end
end
