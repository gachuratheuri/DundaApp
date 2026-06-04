defmodule Dunda.Accounts.OAuth.Sandbox do
  @moduledoc """
  Offline OAuth verifier for dev/test. The "token" is trusted as-is and treated
  as the provider uid; a synthetic profile is returned so the full OAuth →
  find-or-create → token flow can run without contacting Google.

  Optionally encode a richer profile as `uid|email|name`.
  """
  @behaviour Dunda.Accounts.OAuth

  @impl true
  def verify(provider, token) when is_binary(token) and token != "" do
    {uid, email, name} = decode(token)

    {:ok,
     %{
       provider: to_string(provider),
       uid: uid,
       email: email,
       name: name,
       avatar_url: nil
     }}
  end

  def verify(_provider, _token), do: {:error, :invalid_token}

  defp decode(token) do
    case String.split(token, "|") do
      [uid, email, name] -> {uid, email, name}
      [uid, email] -> {uid, email, nil}
      [uid] -> {uid, "#{uid}@sandbox.test", nil}
    end
  end
end
