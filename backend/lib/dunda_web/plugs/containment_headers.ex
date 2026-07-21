defmodule DundaWeb.Plugs.ContainmentHeaders do
  @moduledoc "Adds non-sensitive environment and containment markers to responses."

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    conn
    |> put_resp_header("x-dunda-environment", Dunda.Containment.environment())
    |> maybe_mark_containment()
  end

  defp maybe_mark_containment(conn) do
    if Dunda.Containment.enabled?() do
      put_resp_header(conn, "x-dunda-containment", "phase-0")
    else
      conn
    end
  end
end
