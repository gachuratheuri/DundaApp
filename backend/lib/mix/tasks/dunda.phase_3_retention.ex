defmodule Mix.Tasks.Dunda.Phase3Retention do
  @shortdoc "Previews or executes the conservative Phase 3 retention policy"

  use Mix.Task

  @confirmation "I_UNDERSTAND_PHASE_3_RETENTION"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    report = Dunda.Retention.preview()

    Mix.shell().info("Phase 3 retention preview (financial evidence is protected)")
    Enum.each(report, fn {name, count} -> Mix.shell().info("#{name}=#{count}") end)

    if "--execute" in args do
      if System.get_env("DUNDA_RETENTION_CONFIRM") == @confirmation do
        case Dunda.Retention.execute() do
          {:ok, count} -> Mix.shell().info("deleted_read_notifications=#{count}")
          {:error, reason} -> Mix.raise("retention execution refused: #{reason}")
        end
      else
        Mix.raise("refusing destructive execution; set DUNDA_RETENTION_CONFIRM=#{@confirmation}")
      end
    else
      Mix.shell().info(
        "dry_run=true; pass --execute plus the explicit confirmation to delete eligible notifications"
      )
    end
  end
end
