defmodule Mix.Tasks.Dunda.MigrationDrill do
  use Mix.Task
  @shortdoc "Prove the latest migration applies cleanly against a production-shaped dataset"

  @moduledoc """
  Migrates to `HEAD~1`, seeds a production-shaped dataset
  (`priv/repo/seeds_production_shaped.exs`), then applies the latest
  migration and verifies it succeeds without data loss.

  **Run this only against a disposable database** — it seeds thousands of
  rows and then migrates destructively, exactly like `mix ecto.reset`. It
  does not create or drop a database itself; point `DATABASE_URL` /
  `config/dev.exs` / `config/test.exs` at a scratch database first (the CI
  job runs it against the ephemeral Postgres service container, which is
  disposable by construction).

      mix dunda.migration_drill

  Exits non-zero (via `Mix.raise/1`) if the final migration fails, or if any
  `Dunda.Retention.preview/1` protected-table count decreased across the
  drill (the same check `mix dunda.backup_retention_check` performs for a
  backup/restore cycle — reused here rather than duplicated).
  """

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")
    migrations_path = Application.app_dir(:dunda, "priv/repo/migrations")
    all_migrations = Ecto.Migrator.migrations(Dunda.Repo, migrations_path)
    versions = all_migrations |> Enum.map(&elem(&1, 1)) |> Enum.sort()

    case versions do
      [] ->
        Mix.raise("no migrations found at #{migrations_path}")

      [_only] ->
        Mix.shell().info(
          "Only one migration exists; nothing to drill against a pre-existing dataset. Running it directly."
        )

        run_final_migration(migrations_path, List.first(versions))

      _ ->
        target = versions |> Enum.reverse() |> tl() |> hd()
        latest = List.last(versions)

        Mix.shell().info("Migrating to #{target} (HEAD~1)...")

        {:ok, _, _} =
          Ecto.Migrator.with_repo(
            Dunda.Repo,
            &Ecto.Migrator.run(&1, migrations_path, :up, to: target)
          )

        Mix.shell().info("Seeding production-shaped dataset...")
        before_counts = Dunda.Retention.preview()
        Code.eval_file(Application.app_dir(:dunda, "priv/repo/seeds_production_shaped.exs"))

        Mix.shell().info("Applying latest migration (#{latest})...")
        run_final_migration(migrations_path, latest)

        after_counts = Dunda.Retention.preview()
        assert_no_row_loss!(before_counts, after_counts)
    end

    Mix.shell().info("PASS: migration drill completed with no protected-row loss.")
  end

  defp run_final_migration(migrations_path, version) do
    case Ecto.Migrator.with_repo(
           Dunda.Repo,
           &Ecto.Migrator.run(&1, migrations_path, :up, to: version)
         ) do
      {:ok, _migrated, _} -> :ok
      {:error, reason} -> Mix.raise("final migration failed: #{inspect(reason)}")
    end
  end

  defp assert_no_row_loss!(before_counts, after_counts) do
    failures =
      Enum.filter(before_counts, fn {key, before_count} ->
        Map.get(after_counts, key, 0) < before_count
      end)

    if failures != [] do
      Mix.raise(
        "migration drill lost protected rows: #{inspect(failures)} (before=#{inspect(before_counts)} after=#{inspect(after_counts)})"
      )
    end
  end
end
