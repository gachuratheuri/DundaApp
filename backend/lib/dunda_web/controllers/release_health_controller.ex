defmodule DundaWeb.ReleaseHealthController do
  @moduledoc "Read-only SLO evidence endpoint for controlled releases."

  use DundaWeb, :controller

  def show(conn, _params) do
    if DundaWeb.InternalAuth.authorized?(conn) do
      json(conn, %{release_health: Dunda.ReleaseHealth.evaluate()})
    else
      conn
      |> put_status(:not_found)
      |> json(%{error: %{code: "not_found"}})
    end
  end
end
