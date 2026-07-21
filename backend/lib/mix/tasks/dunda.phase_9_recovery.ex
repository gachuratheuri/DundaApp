defmodule Mix.Tasks.Dunda.Phase9Recovery do
  use Mix.Task
  @shortdoc "Audit or rebuild disposable Redis projections from PostgreSQL"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    {opts, _, _} = OptionParser.parse(args, switches: [report: :boolean, rebuild_redis: :boolean])

    cond do
      opts[:rebuild_redis] ->
        case Dunda.Recovery.rebuild_redis_projection() do
          :ok -> Mix.shell().info("Redis projections rebuilt from PostgreSQL")
          {:error, reason} -> Mix.raise("Redis projection rebuild failed: #{inspect(reason)}")
        end

      opts[:report] ->
        Dunda.Recovery.inventory_projection_report() |> Enum.each(&Mix.shell().info(inspect(&1)))

      true ->
        Mix.raise("choose --report or --rebuild-redis")
    end
  end
end
