defmodule Dunda.Accounts.OAuth.Google do
  @moduledoc """
  Compatibility adapter delegating to the single hardened Google verifier.

  Keeping one implementation prevents callers of the legacy behaviour from
  accidentally bypassing issuer, expiry, audience, or verified-email checks.
  """
  @behaviour Dunda.Accounts.OAuth

  @impl true
  def verify("google", id_token), do: Dunda.Auth.GoogleVerifier.verify(id_token)

  def verify(provider, _token), do: {:error, {:unsupported_provider, provider}}
end
