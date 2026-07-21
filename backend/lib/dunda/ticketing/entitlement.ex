defmodule Dunda.Ticketing.Entitlement do
  @moduledoc """
  Mints offline ticket-entitlement tokens.

  Historical protocol-v1 records are compact ES256 JWS values carrying an
  encrypted TOTP secret. New credentials use `mint_device_bound/3`: the JWS
  carries a protocol version and attendee Ed25519 public key, while the device
  signs each dynamic QR proof. Scanners never receive a private/shared secret.
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
    encrypted_totp_secret = Dunda.Vault.encrypt!(totp_secret) |> url_encode()

    header = %{"alg" => "ES256", "typ" => "JWT"}

    payload =
      %{
        "sub" => ticket_id,
        "totp_secret" => encrypted_totp_secret,
        "iat" => now,
        "exp" => now + ttl
      }
      |> Map.merge(Map.new(Keyword.get(opts, :claims, [])))

    signing_input =
      url_encode(json_encode(header)) <> "." <> url_encode(json_encode(payload))

    {_pub_key, priv_key} = ec_keys()
    der_sig = :crypto.sign(:ecdsa, :sha256, signing_input, [priv_key, :prime256v1])
    signature = der_to_raw(der_sig) |> url_encode()

    {signing_input <> "." <> signature, totp_secret}
  end

  @doc "Mints a protocol-v2 entitlement bound to an attendee Ed25519 public key."
  @spec mint_device_bound(String.t(), binary(), keyword()) :: String.t()
  def mint_device_bound(ticket_id, public_key, opts \\ []) do
    if not Dunda.Ticketing.CredentialProtocol.valid_public_key?(public_key),
      do: raise(ArgumentError, "device public key must be 32-byte Ed25519 key")

    now = Keyword.get(opts, :valid_from, DateTime.utc_now() |> DateTime.truncate(:second))
    valid_until = Keyword.get(opts, :valid_until, DateTime.add(now, 86_400, :second))

    claims =
      %{
        "sub" => ticket_id,
        "protocol_version" => 2,
        "credential_public_key" => Base.url_encode64(public_key, padding: false),
        "iat" => DateTime.to_unix(now),
        "nbf" => DateTime.to_unix(now),
        "exp" => DateTime.to_unix(valid_until)
      }
      |> maybe_put("event_id", Keyword.get(opts, :event_id))
      |> Map.merge(Map.new(Keyword.get(opts, :claims, [])))

    sign_claims(claims)
  end

  @doc "Verifies that an entitlement is protocol v2 and contains a complete binding."
  def verify_device_bound(jwt) when is_binary(jwt) do
    with {:ok, claims} <- verify(jwt),
         2 <- claims["protocol_version"],
         {:ok, public_key} <-
           Dunda.Ticketing.CredentialProtocol.decode(claims["credential_public_key"]),
         true <- Dunda.Ticketing.CredentialProtocol.valid_public_key?(public_key),
         true <- is_integer(claims["nbf"]) and claims["nbf"] <= System.system_time(:second) do
      {:ok, Map.put(claims, "credential_public_key_raw", public_key)}
    else
      _ -> {:error, :not_a_v2_credential}
    end
  end

  def verify_device_bound(_), do: {:error, :not_a_v2_credential}

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
         true <- is_integer(claims["exp"]) and claims["exp"] > System.system_time(:second) do
      {:ok, claims}
    else
      false -> {:error, :invalid_or_expired}
      _ -> {:error, :malformed}
    end
  end

  defp sign_claims(payload) do
    header = %{"alg" => "ES256", "typ" => "JWT", "ver" => 2}
    signing_input = url_encode(json_encode(header)) <> "." <> url_encode(json_encode(payload))
    {_pub_key, priv_key} = ec_keys()
    der_sig = :crypto.sign(:ecdsa, :sha256, signing_input, [priv_key, :prime256v1])
    signing_input <> "." <> (der_to_raw(der_sig) |> url_encode())
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  @doc """
  Verify the JWT signature and verify the dynamic TOTP code against the secret
  in the payload. Supports a customizable `drift_steps` (default 1 step = ±30s)
  to accommodate scanner clock drift.
  """
  @spec verify_with_totp(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, atom()}
  def verify_with_totp(jwt, totp, opts \\ []) do
    drift = Keyword.get(opts, :drift_steps, 1)
    now = System.system_time(:second)

    case verify(jwt) do
      {:ok, claims} ->
        encrypted_secret = claims["totp_secret"]

        with {:ok, decoded_enc} <- safe_url_decode(encrypted_secret),
             {:ok, secret} <- decrypt_secret(decoded_enc) do
          if verify_totp_window(secret, totp, now, drift) do
            {:ok, claims}
          else
            {:error, :invalid_totp}
          end
        else
          _ -> {:error, :decryption_failed}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp decrypt_secret(enc_binary) do
    {:ok, Dunda.Vault.decrypt!(enc_binary)}
  rescue
    e -> {:error, e}
  end

  defp verify_totp_window(secret, totp, now, drift) do
    current_counter = div(now, 30)

    # Check all counters in [current - drift, current + drift]
    Enum.any?((current_counter - drift)..(current_counter + drift), fn c ->
      generate_totp_for_counter(secret, c) == totp
    end)
  end

  defp generate_totp_for_counter(secret, counter) do
    import Bitwise
    msg = <<counter::integer-size(64)-big>>
    {:ok, raw_secret} = safe_url_decode(secret)

    # HMAC-SHA1
    hmac = :crypto.mac(:hmac, :sha, raw_secret, msg)

    # Dynamic truncation
    <<_::binary-size(19), last::integer-size(8)>> = hmac
    offset = last &&& 0x0F

    # Extract 4 bytes starting at offset
    <<_::binary-size(offset), byte1::integer-size(8), byte2::integer-size(8),
      byte3::integer-size(8), byte4::integer-size(8), _::binary>> = hmac

    binary =
      (byte1 &&& 0x7F) <<< 24 |||
        byte2 <<< 16 |||
        byte3 <<< 8 |||
        byte4

    code = rem(binary, 1_000_000)
    to_string(code) |> String.pad_leading(6, "0")
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
