defmodule DundaWeb.HealthController do
  use DundaWeb, :controller

  @doc """
  Readiness/liveness probe. Returns 200 with per-dependency status when healthy,
  503 when a critical dependency (DB or Redis) is unreachable so Kubernetes can
  pull the pod out of rotation.
  """
  def show(conn, params), do: ready(conn, params)

  @doc "Process liveness probe; it deliberately avoids network dependencies."
  def live(conn, _params) do
    json(conn, %{status: "ok"})
  end

  @doc "Dependency readiness probe with bounded database and Redis checks."
  def ready(conn, _params) do
    if File.exists?("/tmp/dunda-draining") do
      conn
      |> put_status(:service_unavailable)
      |> json(%{status: "draining", checks: %{drain: "requested"}})
    else
      checks = %{
        postgres: check_db(),
        redis: check_redis(),
        replica: check_replica()
      }

      status = if Enum.all?(checks, fn {_k, v} -> v == "ok" end), do: 200, else: 503

      conn
      |> put_status(status)
      |> json(%{status: if(status == 200, do: "ok", else: "degraded"), checks: checks})
    end
  end

  defp check_db do
    case Ecto.Adapters.SQL.query(Dunda.Repo, "SELECT 1", [], timeout: 1_000) do
      {:ok, _} -> "ok"
      _ -> "error"
    end
  rescue
    _ -> "error"
  end

  defp check_redis do
    case Redix.command(:redix, ["PING"], timeout: 1_000) do
      {:ok, "PONG"} -> "ok"
      _ -> "error"
    end
  rescue
    _ -> "error"
  end

  defp check_replica do
    sql = "SELECT EXTRACT(EPOCH FROM (clock_timestamp() - pg_last_xact_replay_timestamp()))"

    case Ecto.Adapters.SQL.query(Dunda.ReadRepo, sql, [], timeout: 1_000) do
      {:ok, %{rows: [[nil]]}} -> "ok"
      {:ok, %{rows: [[lag]]}} when is_number(lag) ->
        if lag <= Application.get_env(:dunda, :max_replica_lag_seconds, 30), do: "ok", else: "lagging"

      _ -> "error"
    end
  rescue
    _ -> "error"
  end
end
