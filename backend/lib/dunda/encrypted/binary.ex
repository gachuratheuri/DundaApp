defmodule Dunda.Encrypted.Binary do
  @moduledoc """
  Ecto type that transparently encrypts/decrypts a binary column through
  `Dunda.Vault` (AES-256-GCM). Because GCM is non-deterministic, columns of
  this type CANNOT be used in `WHERE` clauses — pair them with a
  `Dunda.Hashed.HMAC` field for indexed lookups.
  """
  use Cloak.Ecto.Binary, vault: Dunda.Vault
end
