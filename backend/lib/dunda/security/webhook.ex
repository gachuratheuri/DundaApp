defmodule Dunda.Security.Webhook do
  @moduledoc """
  Fail-closed shared-secret verification for provider callbacks.

  Authenticity for providers that do not send custom HTTP headers (e.g. Safaricom Daraja)
  is verified via query parameters (`?secret=...` / `?token=...`) or an upstream edge proxy
  that injects the `x-dunda-webhook-secret` header after initial IP/TLS verification.
  """

  import Plug.Conn, only: [get_req_header: 2]

  @spec valid?(Plug.Conn.t(), atom()) :: boolean()
  def valid?(conn, provider) when provider in [:daraja, :pesapal] do
    configured = (Application.get_env(:dunda, :webhook_secrets) || []) |> Keyword.get(provider)

    params =
      case conn.params do
        %Plug.Conn.Unfetched{} -> %{}
        params when is_map(params) -> params
      end

    supplied =
      get_req_header(conn, "x-dunda-webhook-secret")
      |> List.first() ||
        Map.get(params, "secret") ||
        Map.get(params, "token")

    is_binary(configured) and configured != "" and is_binary(supplied) and
      byte_size(configured) == byte_size(supplied) and
      Plug.Crypto.secure_compare(configured, supplied)
  end
end
