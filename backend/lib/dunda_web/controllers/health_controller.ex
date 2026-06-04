defmodule DundaWeb.HealthController do
  use DundaWeb, :controller

  @doc """
  Readiness/liveness probe. Returns 200 with per-dependency status when healthy,
  503 when a critical dependency (DB or Redis) is unreachable so Kubernetes can
  pull the pod out of rotation.
  """
  def show(conn, _params) do
    checks = %{
      postgres: check_db(),
      redis: check_redis()
    }

    status = if Enum.all?(checks, fn {_k, v} -> v == "ok" end), do: 200, else: 503

    conn
    |> put_status(status)
    |> json(%{status: if(status == 200, do: "ok", else: "degraded"), checks: checks})
  end

  defp check_db do
    case Ecto.Adapters.SQL.query(Dunda.Repo, "SELECT 1", []) do
      {:ok, _} -> "ok"
      _ -> "error"
    end
  rescue
    _ -> "error"
  end

  defp check_redis do
    case Redix.command(:redix, ["PING"]) do
      {:ok, "PONG"} -> "ok"
      _ -> "error"
    end
  rescue
    _ -> "error"
  end
end
