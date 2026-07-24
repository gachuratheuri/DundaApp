defmodule DundaWeb.ErrorCode do
  @moduledoc """
  Stable public error-code boundary.

  Internal structs, database exceptions, provider payloads and arbitrary terms
  must never be serialized into an API response. Only explicitly classified
  atoms/strings cross this boundary.
  """

  @public_atoms ~w(
    admission_already_recorded already_listed already_reserved
    credential_expired credential_invalid credential_revoked
    device_binding_required device_revoked duplicate_admission
    event_not_on_sale expired_quote idempotency_conflict
    idempotency_incomplete idempotency_key_required insufficient_inventory
    invalid_admission invalid_device invalid_idempotency_key invalid_listing
    invalid_price invalid_quantity invalid_quote invalid_signature
    listing_not_active max_per_order_exceeded not_found not_owner
    own_listing payment_pending phase_0_containment quote_consumed
    resale_disabled sold_out ticket_not_active ticket_not_found
    ticket_not_transferable unauthorised unsupported_protocol_version
  )a

  def code(reason) when reason in @public_atoms, do: Atom.to_string(reason)
  def code(reason) when is_binary(reason) and byte_size(reason) <= 80, do: safe_string(reason)
  def code({reason, _detail}), do: code(reason)
  def code(%Ecto.Changeset{}), do: "validation_error"
  def code(_), do: "request_failed"

  defp safe_string(value) do
    if Regex.match?(~r/^[a-z][a-z0-9_]*$/, value), do: value, else: "request_failed"
  end
end
