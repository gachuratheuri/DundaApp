defmodule Mix.Tasks.Dunda.MutationTest do
  use Mix.Task
  @shortdoc "Targeted mutation testing on financial/authorisation-critical guard clauses"

  @moduledoc """
  No maintained free Elixir mutation-testing framework exists (the one
  commercial option, Muzak, requires a paid license this project does not
  have) — recorded explicitly rather than silently skipped. This task is a
  small, honest substitute, deliberately scoped: it applies a **fixed,
  hand-picked, small set of source-text mutations** to the highest-risk
  financial/authorisation guard clauses, runs the specific test file that
  should catch each one in an isolated full-project copy, and reports any
  mutant that *survives* (the test still passes) as a coverage gap.

  This is targeted mutation testing on a whitelist, not full-codebase
  mutation coverage — an honest, bounded claim. Extend `@mutations` below to
  broaden coverage over time.

  Each mutant run copies the whole project (including `deps/` and `_build/`,
  reusing already-fetched/compiled artifacts rather than re-fetching) into a
  scratch directory, applies one source-text substitution, and runs
  `mix test <target file>` there with a unique `MIX_TEST_PARTITION` so it
  gets its own logical test database and cannot collide with a concurrently
  running suite. This is slow (a full project copy per mutant) by design —
  intended for a scheduled/CI-path-filtered run
  (`.github/workflows/ci.yml`'s `mutation-test` job), not routine local dev.

      mix dunda.mutation_test
  """

  @mutations [
    %{
      file: "lib/dunda/checkout.ex",
      original: "p.capacity - p.reserved - p.sold >= ^quote.quantity",
      mutated: "p.capacity - p.reserved - p.sold > ^quote.quantity",
      description:
        "inventory reservation guard >= -> > (Invariant 1: sold + reserved <= capacity)",
      test_file: "test/dunda/inventory_property_test.exs"
    },
    %{
      file: "lib/dunda/checkout/journal.ex",
      original: "if debit_total <= 0 or debit_total != credit_total, do: raise",
      mutated: "if debit_total <= 0 or debit_total == credit_total, do: raise",
      description: "ledger balance guard != -> == (Invariant 4: sum(debits) == sum(credits))",
      test_file: "test/dunda/ledger_property_test.exs"
    },
    %{
      file: "lib/dunda/security/webhook.ex",
      original: "Plug.Crypto.secure_compare(configured, supplied)",
      mutated: "true",
      description: "webhook shared-secret comparison short-circuited to always-valid",
      test_file: "test/dunda/security/webhook_test.exs"
    },
    %{
      file: "lib/dunda/checkout/payment_intent.ex",
      original: "def transition_allowed?(from, to), do: to in Map.get(@transitions, from, [])",
      mutated: "def transition_allowed?(_from, _to), do: true",
      description:
        "payment-intent state machine transition guard disabled (Invariant 8: monotonicity)",
      test_file: "test/dunda/payment_intent_transition_property_test.exs"
    }
  ]

  @impl Mix.Task
  def run(_args) do
    root = File.cwd!()
    Mix.shell().info("Running #{length(@mutations)} targeted mutant(s)...")

    results = Enum.map(@mutations, &run_mutant(root, &1))

    Enum.each(results, fn {mutation, outcome} ->
      Mix.shell().info("  #{mutation.file} — #{mutation.description}: #{outcome_label(outcome)}")
    end)

    survivors = Enum.filter(results, fn {_mutation, outcome} -> outcome == :survived end)
    errors = Enum.filter(results, fn {_mutation, outcome} -> match?({:error, _}, outcome) end)

    cond do
      errors != [] ->
        Mix.raise(
          "#{length(errors)} mutant run(s) errored (see output above) — fix the harness before trusting these results"
        )

      survivors != [] ->
        Mix.raise(
          "#{length(survivors)} mutant(s) SURVIVED — the corresponding test does not cover this guard"
        )

      true ->
        Mix.shell().info("PASS: all #{length(@mutations)} mutants were killed.")
    end
  end

  defp outcome_label(:killed), do: "killed (test failed as expected)"
  defp outcome_label(:survived), do: "SURVIVED (test still passed — coverage gap)"
  defp outcome_label({:error, reason}), do: "ERROR: #{reason}"

  defp run_mutant(root, mutation) do
    scratch = Path.join(System.tmp_dir!(), "dunda-mutant-#{System.unique_integer([:positive])}")

    try do
      copy_project!(root, scratch)
      apply_mutation!(scratch, mutation)
      partition = "mutant#{System.unique_integer([:positive])}"

      {_output, exit_code} =
        System.cmd("mix", ["test", mutation.test_file],
          cd: scratch,
          env: [{"MIX_ENV", "test"}, {"MIX_TEST_PARTITION", partition}],
          stderr_to_stdout: true
        )

      if exit_code == 0, do: {mutation, :survived}, else: {mutation, :killed}
    rescue
      e -> {mutation, {:error, Exception.message(e)}}
    catch
      :exit, reason -> {mutation, {:error, inspect(reason)}}
    after
      File.rm_rf(scratch)
    end
  end

  defp copy_project!(root, scratch) do
    File.mkdir_p!(scratch)

    for entry <- ~w(lib test priv mix.exs mix.lock config deps _build) do
      source = Path.join(root, entry)
      if File.exists?(source), do: File.cp_r!(source, Path.join(scratch, entry))
    end
  end

  defp apply_mutation!(scratch, mutation) do
    path = Path.join(scratch, mutation.file)
    content = File.read!(path)

    unless String.contains?(content, mutation.original) do
      raise "mutation target text not found in #{mutation.file} — the source has drifted from this mutation's expectation; update this task's @mutations"
    end

    File.write!(path, String.replace(content, mutation.original, mutation.mutated, global: false))
  end
end
