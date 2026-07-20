defmodule Mix.Tasks.Dunda.BackupRetentionCheck do
  use Mix.Task
  @shortdoc "Capture or verify that a backup/restore cycle did not lose statutory financial records"

  @moduledoc """
  Executable half of the Phase 11 backup-deletion/retention-implication
  check referenced from `infra/backup/README.md`. It reuses
  `Dunda.Retention.preview/1`'s protected-table counts (ledger entries,
  orders, tickets, audit events — the same tables `Dunda.Retention.execute/1`
  is structurally forbidden from touching) rather than duplicating that list.

  Run before a restore drill (or before a backup's retention window expires
  and it is deleted) to capture a baseline, then again after, to verify no
  statutory financial record count went backwards:

      mix dunda.backup_retention_check --capture-baseline /tmp/baseline.json
      # ... perform the restore drill / let the backup expire ...
      mix dunda.backup_retention_check --verify /tmp/baseline.json

  Exits non-zero on verification failure so it is CI/runbook-automatable.
  """

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    {opts, _, _} = OptionParser.parse(args, switches: [capture_baseline: :string, verify: :string])

    cond do
      opts[:capture_baseline] -> capture(opts[:capture_baseline])
      opts[:verify] -> verify(opts[:verify])
      true -> Mix.raise("choose --capture-baseline <path> or --verify <path>")
    end
  end

  defp capture(path) do
    report = Dunda.Retention.preview()
    File.write!(path, Jason.encode!(report, pretty: true))
    Mix.shell().info("Baseline captured to #{path}: #{inspect(report)}")
  end

  defp verify(path) do
    baseline = path |> File.read!() |> Jason.decode!()
    current = Dunda.Retention.preview() |> Map.new(fn {k, v} -> {to_string(k), v} end)

    failures =
      Enum.filter(protected_keys(), fn key ->
        baseline_count = Map.get(baseline, key, 0)
        current_count = Map.get(current, key, 0)
        current_count < baseline_count
      end)

    if failures == [] do
      Mix.shell().info("PASS: no protected table count decreased. Baseline=#{inspect(baseline)} Current=#{inspect(current)}")
    else
      Mix.shell().error("FAIL: protected table(s) lost rows: #{inspect(failures)}. Baseline=#{inspect(baseline)} Current=#{inspect(current)}")
      Mix.raise("backup retention check failed — statutory financial records were lost")
    end
  end

  defp protected_keys, do: ~w(protected_ledger_entries protected_orders protected_tickets protected_audit_events)
end
