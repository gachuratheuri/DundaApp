defmodule Dunda.Auth.GoogleVerifier do
  @moduledoc """
  Verifies Google ID tokens through Google's token-introspection endpoint.

  The endpoint validates the JWS signature and key rotation server-side. We
  still enforce issuer, audience, expiry, subject, and verified-email claims
  locally before an application identity is created or used.
  """

  @google_tokeninfo "https://oauth2.googleapis.com/tokeninfo"

  @spec verify(String.t()) :: {:ok, map()} | {:error, atom()}
  def verify(token) when is_binary(token) and byte_size(token) <= 4096 do
    with {:ok, %{status: 200, body: claims}} <-
           Req.get(@google_tokeninfo,
             params: [id_token: token],
             max_retries: 0,
             receive_timeout: 5_000
           ),
         :ok <- validate_claims(claims) do
      {:ok,
       %{
         provider: "google",
         uid: claims["sub"],
         email: claims["email"],
         name: claims["name"],
         avatar_url: claims["picture"]
       }}
    else
      {:ok, %{status: _status}} -> {:error, :invalid_google_token}
      {:error, _reason} -> {:error, :google_verification_unavailable}
      {:error, reason} when is_atom(reason) -> {:error, reason}
      _ -> {:error, :invalid_google_token}
    end
  end

  def verify(_), do: {:error, :invalid_google_token}

  defp validate_claims(claims) when is_map(claims) do
    now = System.system_time(:second)
    expected_audience = Application.get_env(:dunda, :google_client_id)
    issuer = claims["iss"]
    audience = claims["aud"]
    expiry = parse_integer(claims["exp"])

    cond do
      issuer not in ["accounts.google.com", "https://accounts.google.com"] ->
        {:error, :invalid_google_issuer}

      is_binary(expected_audience) and expected_audience != "" and audience != expected_audience ->
        {:error, :invalid_google_audience}

      is_nil(expected_audience) or expected_audience == "" ->
        {:error, :google_audience_not_configured}

      is_nil(claims["sub"]) or claims["sub"] == "" ->
        {:error, :invalid_google_subject}

      not valid_claim_string?(claims["sub"], 256) ->
        {:error, :invalid_google_subject}

      not valid_claim_string?(claims["email"], 320) ->
        {:error, :invalid_google_email}

      claims["email_verified"] not in [true, "true"] ->
        {:error, :google_email_not_verified}

      is_nil(expiry) or expiry <= now ->
        {:error, :expired_google_token}

      true ->
        :ok
    end
  end

  defp validate_claims(_), do: {:error, :invalid_google_claims}

  defp parse_integer(value) when is_integer(value), do: value

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _ -> nil
    end
  end

  defp parse_integer(_), do: nil

  defp valid_claim_string?(value, max_bytes)
       when is_binary(value) and byte_size(value) > 0 and byte_size(value) <= max_bytes,
       do: true

  defp valid_claim_string?(_, _), do: false
end
