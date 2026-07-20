defmodule Dunda.Vault.KeyProvider.Env do
  @moduledoc """
  Default `Dunda.Vault.KeyProvider` adapter: resolves base64-encoded key
  material from environment variables. This is the adapter with real
  credentials wired up in every environment this codebase has run in; a
  cloud-KMS-backed adapter implementing the same behaviour can be introduced
  later without touching `config/runtime.exs` beyond the adapter name (see
  the module doc on `Dunda.Vault.KeyProvider`).
  """
  @behaviour Dunda.Vault.KeyProvider

  @env_vars %{
    encryption_key: "ENCRYPTION_KEY",
    encryption_key_previous: "ENCRYPTION_KEY_PREVIOUS",
    blind_index_key: "BLIND_INDEX_KEY"
  }

  @impl true
  def fetch_key(name) when is_map_key(@env_vars, name) do
    @env_vars
    |> Map.fetch!(name)
    |> System.get_env()
    |> decode()
  end

  def fetch_key(_name), do: {:error, :unknown_key}

  defp decode(nil), do: {:error, :not_configured}
  defp decode(""), do: {:error, :not_configured}

  defp decode(value) do
    case Base.decode64(value) do
      {:ok, decoded} -> {:ok, decoded}
      :error -> {:error, :invalid_key_encoding}
    end
  end
end
