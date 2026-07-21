defmodule DundaWeb.ContainmentController do
  @moduledoc "Stable, non-sensitive responses for operations disabled by Phase 0."

  use DundaWeb, :controller

  def disabled(conn, _params) do
    conn
    |> put_status(:service_unavailable)
    |> put_resp_header("retry-after", "86400")
    |> put_resp_header("x-dunda-containment", "phase-0")
    |> put_resp_header("x-dunda-environment", Dunda.Containment.environment())
    |> json(%{
      error: %{
        code: "phase_0_containment",
        message: "This operation is disabled while Dunda is in emergency containment mode."
      }
    })
  end
end
