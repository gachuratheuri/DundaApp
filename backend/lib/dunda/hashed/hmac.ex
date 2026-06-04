defmodule Dunda.Hashed.HMAC do
  @moduledoc """
  Deterministic HMAC-SHA256 Ecto type used for blind-indexed lookups of
  values that are otherwise stored encrypted (e.g. `phone_msisdn_hash`).

  The HMAC key is distinct from the AES encryption key so that compromise of
  one does not compromise the other.
  """
  use Cloak.Ecto.HMAC, otp_app: :dunda
end
