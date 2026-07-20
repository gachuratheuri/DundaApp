defmodule DundaWeb.Plugs.RequestMetrics do
  @moduledoc "Captures bounded request counters without recording query strings or bodies."

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    started = System.monotonic_time(:microsecond)

    register_before_send(conn, fn conn ->
      route = normalize_route(conn.request_path)
      duration = System.monotonic_time(:microsecond) - started
      Dunda.Observability.observe_request(route, conn.status || 500, duration)
      conn
    end)
  end

  defp normalize_route(path) do
    path
    |> String.split("/", trim: true)
    |> Enum.map(fn segment ->
      if Regex.match?(~r/^(\d+|[0-9a-fA-F-]{16,})$/, segment), do: ":id", else: segment
    end)
    |> then(fn [] -> "/"; segments -> "/" <> Enum.join(segments, "/") end)
  end
end
