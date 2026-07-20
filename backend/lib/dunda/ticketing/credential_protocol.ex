defmodule Dunda.Ticketing.CredentialProtocol do
  @moduledoc """
  Version 2 ticket proof protocol.

  A scanner verifies the server-signed entitlement and an Ed25519 proof made
  by the attendee device. No scanner receives a shared signing secret. The
  canonical encoding is deliberately language-neutral and is mirrored by the
  TypeScript and Kotlin implementations in the repository.
  """

  @version 2
  @period_seconds 30
  @nonce_bytes 16

  def version, do: @version
  def period_seconds, do: @period_seconds

  @spec canonical_proof(map()) :: binary()
  def canonical_proof(%{ticket_id: ticket_id, event_id: event_id, time_step: step, nonce: nonce, credential_public_key: key}) do
    ["dunda-ticket-proof", "v=2", "ticket_id=#{to_string(ticket_id)}", "event_id=#{to_string(event_id)}", "time_step=#{to_string(step)}", "nonce=#{encode(nonce)}", "credential_public_key=#{encode(key)}"]
    |> Enum.join("\n")
  end

  def canonical_proof(_), do: raise(ArgumentError, "incomplete ticket proof")

  def generate_nonce, do: :crypto.strong_rand_bytes(@nonce_bytes)

  def valid_public_key?(key), do: is_binary(key) and byte_size(key) == 32
  def valid_signature?(signature), do: is_binary(signature) and byte_size(signature) == 64

  def canonical_binding(ticket_id, user_id, challenge) do
    ["dunda-ticket-device-binding", "v=2", "ticket_id=#{to_string(ticket_id)}", "user_id=#{to_string(user_id)}", "challenge=#{encode(challenge)}"]
    |> Enum.join("\n")
  end

  def canonical_scanner_request(device_id, event_id, admission_id, proof_nonce, request_nonce) do
    ["dunda-scanner-admission", "v=2", "device_id=#{to_string(device_id)}", "event_id=#{to_string(event_id)}", "admission_id=#{to_string(admission_id)}", "proof_nonce=#{encode(proof_nonce)}", "request_nonce=#{encode(request_nonce)}"]
    |> Enum.join("\n")
  end

  def verify_device_signature(public_key, payload, signature) do
    if valid_public_key?(public_key) and valid_signature?(signature) do
      :crypto.verify(:eddsa, :none, payload, signature, [public_key, :ed25519])
    else
      false
    end
  rescue
    _ -> false
  end

  @doc "Verifies an Ed25519 proof without requiring a private/shared secret."
  def verify_proof(%{ticket_id: ticket_id, event_id: event_id, time_step: step, nonce: nonce, credential_public_key: key, signature: signature}, opts \\ []) do
    with true <- valid_public_key?(key),
         true <- valid_signature?(signature),
         true <- is_integer(step) and step >= 0,
         true <- is_binary(nonce) and byte_size(nonce) in 16..64,
         true <- valid_time_step?(step, Keyword.get(opts, :now, System.system_time(:second)), Keyword.get(opts, :drift_steps, 1)),
         true <- :crypto.verify(:eddsa, :none, canonical_proof(%{ticket_id: ticket_id, event_id: event_id, time_step: step, nonce: nonce, credential_public_key: key}), signature, [key, :ed25519]) do
      :ok
    else
      false -> {:error, :invalid_ticket_proof}
      _ -> {:error, :invalid_ticket_proof}
    end
  rescue
    _ -> {:error, :invalid_ticket_proof}
  end

  def verify_proof(_, _), do: {:error, :invalid_ticket_proof}

  def valid_time_step?(step, now, drift_steps) when is_integer(step) and is_integer(now) and is_integer(drift_steps) and drift_steps >= 0 do
    current = div(now, @period_seconds)
    abs(step - current) <= drift_steps
  end

  def valid_time_step?(_, _, _), do: false

  def encode(value) when is_binary(value), do: Base.url_encode64(value, padding: false)
  def encode(value), do: value |> to_string() |> Base.url_encode64(padding: false)

  def decode(value) when is_binary(value) do
    case Base.url_decode64(value, padding: false) do
      {:ok, decoded} -> {:ok, decoded}
      _ -> {:error, :invalid_base64url}
    end
  end

  def decode(_), do: {:error, :invalid_base64url}
end
