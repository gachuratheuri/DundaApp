defmodule Dunda.Accounts.OAuth.Google do
  @moduledoc """
  Verifies a Google ID token server-side via Google's tokeninfo endpoint and
  returns a normalised profile.

  The mobile app obtains the ID token through the native Google Sign-In SDK and
  posts it to `/api/auth/oauth`. We re-verify it here (never trusting the client)
  and, when configured, assert the `aud` matches our OAuth client id.

  Config (optional `client_id` hardens audience validation):

      config :dunda, :oauth,
        adapter: Dunda.Accounts.OAuth.Google,
        google_client_id: System.get_env("GOOGLE_OAUTH_CLIENT_ID")
  """
  @behaviour Dunda.Accounts.OAuth

  require Logger

  @tokeninfo "https://oauth2.googleapis.com/tokeninfo"

  @impl true
  def verify("google", id_token) when is_binary(id_token) do
    case Req.get(@tokeninfo, params: [id_token: id_token], max_retries: 1, receive_timeout: 10_000) do
      {:ok, %{status: 200, body: %{"sub" => sub} = claims}} ->
        with :ok <- check_audience(claims) do
          {:ok,
           %{
             provider: "google",
             uid: sub,
             email: claims["email"],
             name: claims["name"],
             avatar_url: claims["picture"]
           }}
        end

      {:ok, %{status: status, body: body}} ->
        Logger.warning("[Google OAuth] tokeninfo #{status}: #{inspect(body)}")
        {:error, :invalid_token}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def verify(provider, _token), do: {:error, {:unsupported_provider, provider}}

  defp check_audience(%{"aud" => aud}) do
    case Application.get_env(:dunda, :oauth, []) |> Keyword.get(:google_client_id) do
      nil -> :ok
      ^aud -> :ok
      _ -> {:error, :audience_mismatch}
    end
  end

  defp check_audience(_), do: {:error, :audience_mismatch}
end
