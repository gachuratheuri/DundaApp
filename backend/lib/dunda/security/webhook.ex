defmodule Dunda.Security.Webhook do
  @moduledoc """Fail-closed shared-secret verification for provider callbacks."""

  import Plug.Conn, only: [get_req_header: 2]

  @spec valid?(Plug.Conn.t(), atom()) :: boolean()
  def valid?(conn, provider) when provider in [:daraja, :pesapal] do
    configured = (Application.get_env(:dunda, :webhook_secrets) || []) |> Keyword.get(provider)
    supplied = get_req_header(conn, "x-dunda-webhook-secret") |> List.first()

    is_binary(configured) and configured != "" and is_binary(supplied) and
      byte_size(configured) == byte_size(supplied) and
      Plug.Crypto.secure_compare(configured, supplied)
  end
end
