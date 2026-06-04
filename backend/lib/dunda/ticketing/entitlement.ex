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

    header = %{"alg" => "ES256", "typ" => "JWT"}

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

    {pub_key, priv_key} = ec_keys()
    der_sig = :crypto.sign(:ecdsa, :sha256, signing_input, [priv_key, :prime256v1])
    signature = der_to_raw(der_sig) |> url_encode()

    {signing_input <> "." <> signature, totp_secret}
  end

  @doc "Verify a token's signature and expiry, returning the decoded claims."
  @spec verify(String.t()) :: {:ok, map()} | {:error, atom()}
  def verify(jwt) do
    with [h, p, s] <- String.split(jwt, "."),
         {:ok, sig_raw} <- safe_url_decode(s),
         der_sig <- raw_to_der(sig_raw),
         {pub_key, _priv_key} = ec_keys(),
         true <- :crypto.verify(:ecdsa, :sha256, h <> "." <> p, der_sig, [pub_key, :prime256v1]),
         {:ok, payload_bin} <- safe_url_decode(p),
         {:ok, claims} <- json_decode(payload_bin),
         true <- claims["exp"] > System.system_time(:second) do
      {:ok, claims}
    else
      false -> {:error, :invalid_or_expired}
      _ -> {:error, :malformed}
    end
  end

  defp generate_secret, do: url_encode(:crypto.strong_rand_bytes(20))

  defp ec_keys do
    priv = raw_private_key()
    {pub, _} = :crypto.generate_key(:ecdh, :prime256v1, priv)
    {pub, priv}
  end

  defp raw_private_key do
    key = signing_key()
    case Base.decode64(key) do
      {:ok, decoded} when byte_size(decoded) == 32 -> decoded
      _ -> :crypto.hash(:sha256, key)
    end
  end

  defp signing_key do
    Application.fetch_env!(:dunda, DundaWeb.Endpoint)
    |> Keyword.fetch!(:entitlement_signing_key)
  end

  defp der_to_raw(der) do
    {:ECDSA_Sig_Value, r, s} = :public_key.der_decode(:ECDSA_Sig_Value, der)
    pad_32(:binary.encode_unsigned(r)) <> pad_32(:binary.encode_unsigned(s))
  end

  defp raw_to_der(<<r_bin::binary-size(32), s_bin::binary-size(32)>>) do
    r = :binary.decode_unsigned(r_bin)
    s = :binary.decode_unsigned(s_bin)
    :public_key.der_encode(:ECDSA_Sig_Value, {:ECDSA_Sig_Value, r, s})
  end
  defp raw_to_der(_), do: <<>>

  defp pad_32(bin) do
    case 32 - byte_size(bin) do
      0 -> bin
      n when n > 0 -> String.duplicate(<<0>>, n) <> bin
    end
  end

  defp safe_url_decode(str) do
    case Base.url_decode64(str, padding: false) do
      {:ok, decoded} -> {:ok, decoded}
      _ -> {:error, :malformed}
    end
  end

  defp json_encode(map), do: Jason.encode!(map)
  defp json_decode(bin), do: Jason.decode(bin)

  defp url_encode(bin), do: Base.url_encode64(bin, padding: false)
end
