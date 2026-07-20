defmodule Mix.Tasks.Dunda.Phase5Readiness do
  @shortdoc "Reports post-release SLO and governance evidence without mutating state"

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    Mix.shell().info("Phase 5 post-release readiness report (read-only)")
    Mix.shell().info("environment=#{Dunda.Containment.environment()}")
    Mix.shell().info("containment_mode=#{Dunda.Containment.enabled?()}")
    report = Dunda.ReleaseHealth.evaluate()
    Mix.shell().info("release_health=#{inspect(report)}")

    Enum.each(Dunda.Containment.blocked_features(), fn feature ->
      Mix.shell().info("gate.#{feature}=#{inspect(Dunda.ReleaseApprovals.status(feature))}")
    end)

    if report.healthy do
      :ok
    else
      Mix.raise("Phase 5 SLO guardrail is unhealthy; retain or revoke the release approval")
    end
  end
end
