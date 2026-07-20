defmodule DundaWeb.Plugs.SecurityHeaders do
  @moduledoc """Explicit browser security policy for API and organiser responses."""

  import Plug.Conn

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    conn
    |> put_resp_header("x-content-type-options", "nosniff")
    |> put_resp_header("x-frame-options", "DENY")
    |> put_resp_header("referrer-policy", "no-referrer")
    |> put_resp_header("permissions-policy", "camera=(), microphone=(), geolocation=()")
    |> put_resp_header("content-security-policy", csp())
    |> maybe_hsts()
  end

  defp csp do
    "default-src 'self'; base-uri 'self'; frame-ancestors 'none'; " <>
      "object-src 'none'; form-action 'self'; img-src 'self' data: https:; " <>
      "style-src 'self' 'unsafe-inline'; script-src 'self'; connect-src 'self' wss:"
  end

  defp maybe_hsts(conn) do
    if Application.get_env(:dunda, :secure_cookies, false) do
      put_resp_header(conn, "strict-transport-security", "max-age=31536000; includeSubDomains")
    else
      conn
    end
  end
end
