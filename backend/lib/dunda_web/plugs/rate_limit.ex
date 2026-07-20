defmodule DundaWeb.Plugs.RateLimit do
  @moduledoc """
  Redis-backed fixed-window rate limiter for API perimeters.

  The counter and expiry are set by one Lua script, avoiding the race where a
  process increments a new key but crashes before applying its expiry.  Client
  identity is deliberately based on the socket address; forwarded headers are
  not trusted unless a separately reviewed proxy-trust plug is introduced.
  """

  import Plug.Conn

  @script """
  local count = redis.call('INCR', KEYS[1])
  if count == 1 then
    redis.call('EXPIRE', KEYS[1], ARGV[1])
  end
  return count
  """

  @spec init(keyword()) :: keyword()
  def init(opts) do
    opts
    |> Keyword.validate!(
      scope: "api",
      limit: 120,
      window_seconds: 60,
      fail_closed: true
    )
  end

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    scope = Keyword.fetch!(opts, :scope)
    limit = Keyword.fetch!(opts, :limit)
    window = Keyword.fetch!(opts, :window_seconds)
    key = "ratelimit:v1:#{scope}:#{client_key(conn)}"

    case Redix.command(:redix, ["EVAL", @script, "1", key, to_string(window)]) do
      {:ok, count} when is_integer(count) and count <= limit ->
        conn

      {:ok, count} when is_binary(count) ->
        handle_count(conn, String.to_integer(count), key, limit)

      {:ok, count} when is_integer(count) ->
        handle_count(conn, count, key, limit)

      {:error, _reason} ->
        if Keyword.fetch!(opts, :fail_closed) do
          conn
          |> put_status(:service_unavailable)
          |> put_resp_header("retry-after", "5")
          |> Phoenix.Controller.json(%{error: %{code: "rate_limiter_unavailable"}})
          |> halt()
        else
          conn
        end
    end
  rescue
    _reason ->
      if Keyword.fetch!(opts, :fail_closed) do
        conn
        |> put_status(:service_unavailable)
        |> put_resp_header("retry-after", "5")
        |> Phoenix.Controller.json(%{error: %{code: "rate_limiter_unavailable"}})
        |> halt()
      else
        conn
      end
  end

  defp handle_count(conn, count, _key, limit) when count <= limit, do: conn

  defp handle_count(conn, _count, key, _limit) do
    Dunda.Observability.increment(:rate_limited)
    retry_after =
      case Redix.command(:redix, ["TTL", key]) do
        {:ok, ttl} when is_integer(ttl) and ttl > 0 -> ttl
        _ -> 1
      end

    conn
    |> put_status(:too_many_requests)
    |> put_resp_header("retry-after", Integer.to_string(retry_after))
    |> Phoenix.Controller.json(%{error: %{code: "rate_limited"}})
    |> halt()
  end

  defp client_key(%Plug.Conn{remote_ip: remote_ip}), do: :inet.ntoa(remote_ip) |> to_string()
end
