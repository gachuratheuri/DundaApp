defmodule Mix.Tasks.Dunda.RotateKeys do
  use Mix.Task
  @shortdoc "Re-encrypt Vault fields / rehash the blind index under the current key material"

  @moduledoc """
  Executable half of the Phase 11 key-rotation runbook — see
  `docs/phase_11_privacy_governance.md` § Key rotation for the full
  env-var/deploy sequence this task assumes has already happened.

      mix dunda.rotate_keys --reencrypt      # re-save every Dunda.Encrypted.Binary field
      mix dunda.rotate_keys --blind-index    # rehash User.phone_msisdn_hash
      mix dunda.rotate_keys --reencrypt --blind-index

  Idempotent: safe to re-run. Every invocation is itself audited.
  """

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    {opts, _, _} = OptionParser.parse(args, switches: [reencrypt: :boolean, blind_index: :boolean])

    if not (opts[:reencrypt] || opts[:blind_index]) do
      Mix.raise("choose --reencrypt and/or --blind-index")
    end

    if opts[:reencrypt] do
      results = Dunda.Vault.Rotation.reencrypt_all()

      Enum.each(results, fn {schema, %{migrated: migrated, failed: failed}} ->
        Mix.shell().info("#{inspect(schema)}: migrated=#{migrated} failed=#{failed}")
      end)

      _ =
        Dunda.Audit.record(%{
          action: "vault.reencrypt_all",
          resource_type: "vault_rotation",
          metadata: %{
            results: Map.new(results, fn {schema, outcome} -> {inspect(schema), outcome} end)
          }
        })
    end

    if opts[:blind_index] do
      %{migrated: migrated, failed: failed} = outcome = Dunda.Vault.Rotation.rehash_blind_index()
      Mix.shell().info("blind_index: migrated=#{migrated} failed=#{failed}")
      _ = Dunda.Audit.record(%{action: "vault.rehash_blind_index", resource_type: "vault_rotation", metadata: outcome})
    end
  end
end
