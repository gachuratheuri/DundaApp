defmodule Dunda.Ticketing.ManifestProtocol do
  @moduledoc "Signed event-manifest protocol for venue-local coordinators."

  def canonical_payload(payload) when is_map(payload), do: Jason.encode!(sort_value(payload))

  def sign(payload) do
    private = key(:scanner_manifest_private_key)
    :crypto.sign(:eddsa, :none, canonical_payload(payload), [private, :ed25519])
  end

  def verify(payload, signature) when is_binary(signature) do
    public = key(:scanner_manifest_public_key)
    :crypto.verify(:eddsa, :none, canonical_payload(payload), signature, [public, :ed25519])
  rescue
    _ -> false
  end

  def key_id, do: Application.get_env(:dunda, :scanner_manifest_key_id, "manifest-v1")

  def public_key, do: key(:scanner_manifest_public_key)

  defp key(:scanner_manifest_public_key), do: configured_key(:scanner_manifest_public_key)

  defp key(name), do: configured_key(name)

  defp configured_key(name) do
    value = Application.get_env(:dunda, name, "") |> to_string()

    case Base.decode64(value) do
      {:ok, raw} when byte_size(raw) == 32 -> raw
      _ -> raise ArgumentError, "#{name} must be base64-encoded 32-byte Ed25519 key material"
    end
  end

  defp sort_value(map) when is_map(map),
    do:
      map
      |> Enum.sort_by(fn {key, _} -> to_string(key) end)
      |> Map.new(fn {key, value} -> {to_string(key), sort_value(value)} end)

  defp sort_value(list) when is_list(list), do: Enum.map(list, &sort_value/1)
  defp sort_value(value), do: value
end
