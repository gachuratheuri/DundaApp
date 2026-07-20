defmodule Mix.Tasks.Dunda.Phase4Release do
  @shortdoc "Reports persisted Phase 4 release gates without changing them"

  use Mix.Task

  @features Dunda.Containment.blocked_features()

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")
    Mix.shell().info("Phase 4 release gate report (read-only)")
    Mix.shell().info("gate_enforced=#{Application.get_env(:dunda, :phase4_gate_enforced, true)}")

    Enum.each(@features, fn feature ->
      Mix.shell().info("#{feature}=#{inspect(Dunda.ReleaseApprovals.status(feature))}")
    end)

    :ok
  end
end
