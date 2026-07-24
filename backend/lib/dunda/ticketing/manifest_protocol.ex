defmodule Dunda.Ticketing.ManifestProtocol do
  @moduledoc "Signed event-manifest protocol for venue-local coordinators."

  def canonical_payload(payload) when is_map(payload), do: Jason.encode!(sort_value(payload))

  def signed_document(event_id, version, key_id, valid_from, valid_until, payload) do
    %{
      protocol: "dunda-scanner-manifest",
      protocol_version: 2,
      event_id: event_id,
      version: version,
      key_id: key_id,
      valid_from: iso8601(valid_from),
      valid_until: iso8601(valid_until),
      payload: payload
    }
  end

  def sign(document) do
    private = key(:scanner_manifest_private_key)
    :crypto.sign(:eddsa, :none, canonical_payload(document), [private, :ed25519])
  end

  def verify(document, signature) when is_binary(signature) do
    public = key(:scanner_manifest_public_key)
    :crypto.verify(:eddsa, :none, canonical_payload(document), signature, [public, :ed25519])
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
  defp iso8601(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp iso8601(value) when is_binary(value), do: value
end
