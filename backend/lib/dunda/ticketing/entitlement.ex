defmodule Dunda.Ticketing.Entitlement do
  @moduledoc """
  Mints offline ticket-entitlement tokens.

  The token is a compact JWS (`header.payload.signature`) signed with HMAC-SHA256
  over the configured `:entitlement_signing_key`. The payload carries a
  per-ticket `totp_secret`; the holder's device derives a rotating RFC 6238 code
  from it (see the app's `useTicketTOTP`), and the venue scanner validates the
  `<jwt>.<totp>` pair offline.

  NOTE: production should migrate to ECDSA P-256 (ES256) so scanners verify with
  a public key only — the signing primitive is intentionally isolated here.
  """

  @doc """
  Mint a token for `ticket_id` valid for `ttl_seconds` (default 24h). Returns
  `{jwt, totp_secret}`.
  """
  @spec mint(String.t(), keyword()) :: {String.t(), String.t()}
  def mint(ticket_id, opts \\ []) do
    ttl = Keyword.get(opts, :ttl_seconds, 86_400)
    now = System.system_time(:second)
    totp_secret = generate_secret()

    header = %{"alg" => "HS256", "typ" => "JWT"}

    payload =
      %{
        "sub" => ticket_id,
        "totp_secret" => totp_secret,
        "iat" => now,
        "exp" => now + ttl
      }
      |> Map.merge(Map.new(Keyword.get(opts, :claims, [])))

    signing_input =
      url_encode(json_encode(header)) <> "." <> url_encode(json_encode(payload))

    signature = url_encode(:crypto.mac(:hmac, :sha256, signing_key(), signing_input))

    {signing_input <> "." <> signature, totp_secret}
  end

  @doc "Verify a token's signature and expiry, returning the decoded claims."
  @spec verify(String.t()) :: {:ok, map()} | {:error, atom()}
  def verify(jwt) do
    with [h, p, s] <- String.split(jwt, "."),
         expected <- url_encode(:crypto.mac(:hmac, :sha256, signing_key(), h <> "." <> p)),
         true <- Plug.Crypto.secure_compare(s, expected),
         {:ok, claims} <- json_decode(url_decode(p)),
         true <- claims["exp"] > System.system_time(:second) do
      {:ok, claims}
    else
      false -> {:error, :invalid_or_expired}
      _ -> {:error, :malformed}
    end
  end

  defp generate_secret, do: url_encode(:crypto.strong_rand_bytes(20))

  defp signing_key do
    Application.fetch_env!(:dunda, DundaWeb.Endpoint)
    |> Keyword.fetch!(:entitlement_signing_key)
  end

  defp json_encode(map), do: Jason.encode!(map)
  defp json_decode(bin), do: Jason.decode(bin)

  defp url_encode(bin), do: Base.url_encode64(bin, padding: false)
  defp url_decode(str), do: Base.url_decode64!(str, padding: false)
end
