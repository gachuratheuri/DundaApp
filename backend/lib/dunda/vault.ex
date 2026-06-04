defmodule Dunda.Vault do
  @moduledoc """
  Cloak vault used for AES-256-GCM column-level encryption of PII.

  Ciphers are configured at runtime (see `config/runtime.exs`) so the
  `ENCRYPTION_KEY` is never compiled into the release.
  """
  use Cloak.Vault, otp_app: :dunda
end
