defmodule Dunda.Vault.Rotation do
  @moduledoc """
  Executable half of the key-rotation runbook
  (`docs/phase_11_privacy_governance.md` § Key rotation).

  `reencrypt_all/0` re-saves every `Dunda.Encrypted.Binary` field so it is
  written under the currently configured `default` `Dunda.Vault` cipher.
  `rehash_blind_index/0` recomputes `Dunda.Accounts.User.phone_msisdn_hash`
  under the currently configured `Dunda.Hashed.HMAC` secret from the
  independently-stored plaintext (`phone_msisdn`, decrypted transparently by
  Cloak on load) — never from the old hash, which is one-way.

  Both functions are idempotent and safe to re-run: a row already on the
  current key/secret is rewritten to the same ciphertext/hash and counted as
  migrated. There is deliberately no separate "how many rows are still on the
  old generation" report — Cloak's on-disk ciphertext format is not a public,
  version-stable contract this codebase should parse by hand. The
  authoritative completion signal is running this task again: once
  `migrated: 0, failed: 0` on a second consecutive run, rotation is complete
  and the operator may remove `ENCRYPTION_KEY_PREVIOUS`/`BLIND_INDEX_KEY_PREVIOUS`.
  """

  import Ecto.Query
  alias Dunda.Repo

  @type outcome :: %{migrated: non_neg_integer(), failed: non_neg_integer()}

  # {schema, [Dunda.Encrypted.Binary fields]}
  @encrypted_targets [
    {Dunda.Accounts.User, [:phone_msisdn, :device_fingerprint]},
    {Dunda.Billing.Order, [:phone_encrypted]},
    {Dunda.Checkout.PaymentIntent, [:phone_encrypted]},
    {Dunda.Organisations.Organisation, [:mpesa_phone_encrypted]},
    {Dunda.Organisations.Payout, [:mpesa_phone_encrypted]}
  ]

  @spec encrypted_targets() :: [{module(), [atom()]}]
  def encrypted_targets, do: @encrypted_targets

  @spec reencrypt_all() :: %{module() => outcome()}
  def reencrypt_all do
    Map.new(@encrypted_targets, fn {schema, fields} -> {schema, reencrypt_schema(schema, fields)} end)
  end

  @spec rehash_blind_index() :: outcome()
  def rehash_blind_index do
    {:ok, outcome} =
      Repo.transaction(
        fn ->
          Dunda.Accounts.User
          |> where([u], not is_nil(u.phone_msisdn))
          |> Repo.stream()
          |> Enum.reduce(%{migrated: 0, failed: 0}, &rehash_one/2)
        end,
        timeout: :infinity
      )

    outcome
  end

  defp reencrypt_schema(schema, fields) do
    {:ok, outcome} =
      Repo.transaction(
        fn ->
          schema
          |> Repo.stream()
          |> Enum.reduce(%{migrated: 0, failed: 0}, &reencrypt_one(&1, &2, fields))
        end,
        timeout: :infinity
      )

    outcome
  end

  defp reencrypt_one(row, acc, fields) do
    non_nil_fields = Enum.filter(fields, &(Map.get(row, &1) != nil))

    if non_nil_fields == [] do
      acc
    else
      changeset =
        Enum.reduce(non_nil_fields, Ecto.Changeset.change(row), fn field, changeset ->
          Ecto.Changeset.force_change(changeset, field, Map.get(row, field))
        end)

      persist(changeset, acc)
    end
  end

  defp rehash_one(user, acc) do
    changeset = Ecto.Changeset.force_change(Ecto.Changeset.change(user), :phone_msisdn_hash, user.phone_msisdn)
    persist(changeset, acc)
  end

  defp persist(changeset, acc) do
    case Repo.update(changeset) do
      {:ok, _row} -> %{acc | migrated: acc.migrated + 1}
      {:error, _changeset} -> %{acc | failed: acc.failed + 1}
    end
  end
end
