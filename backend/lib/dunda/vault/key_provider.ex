defmodule Dunda.Vault.KeyProvider do
  @moduledoc """
  Behaviour for resolving Dunda's encryption and blind-index key material.

  `config/runtime.exs` never calls `System.fetch_env!/1` for key bytes
  directly; it goes through a configured adapter — the same seam already used
  for `Dunda.Payments.Daraja` (`.HTTP` / `.Sandbox`) and `Dunda.Billing.Pesapal`
  (`.HTTP` / `.Sandbox`). This makes swapping the environment-variable default
  for a real cloud KMS/secrets-manager adapter (AWS KMS, GCP Cloud KMS,
  HashiCorp Vault Transit — envelope-decrypting a wrapped data-encryption-key
  at boot) a one-module addition with zero call-site churn, without this
  codebase committing to a cloud provider it cannot exercise with real
  credentials. See `docs/phase_11_privacy_governance.md` § Key management.
  """

  @type key_name :: :encryption_key | :encryption_key_previous | :blind_index_key

  @doc """
  Resolves the named key to raw bytes. `_previous` variants are optional
  (used only during a key-rotation grace window) and MUST return
  `{:error, :not_configured}`, never raise, when absent.
  """
  @callback fetch_key(key_name()) :: {:ok, binary()} | {:error, term()}

  @doc "Resolves a required key, raising with an actionable message if absent."
  @spec fetch_key!(module(), key_name()) :: binary()
  def fetch_key!(provider, name) do
    case provider.fetch_key(name) do
      {:ok, key} when is_binary(key) and byte_size(key) > 0 ->
        key

      {:error, reason} ->
        raise "#{inspect(provider)} could not resolve required key #{name}: #{inspect(reason)}"
    end
  end

  @doc "Resolves an optional (rotation-grace-window) key. Returns nil when absent."
  @spec fetch_key_optional(module(), key_name()) :: binary() | nil
  def fetch_key_optional(provider, name) do
    case provider.fetch_key(name) do
      {:ok, key} when is_binary(key) and byte_size(key) > 0 -> key
      {:error, _reason} -> nil
    end
  end
end
