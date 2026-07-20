defmodule Dunda.Workers.IngestWorker do
  @moduledoc """
  The unified seam (queue `scrape_ingest`, concurrency 10).

  Every fetch worker — regardless of source — funnels its raw events here. The
  ingest worker calls `Normaliser.normalise/3` with the `organisation_id` carried
  from dispatch metadata, then runs each canonical event through the
  Bloom → DB idempotent upsert in `Dunda.Scraper.upsert_event/1`.
  """
  use Oban.Worker, queue: :scrape_ingest, max_attempts: 5

  require Logger

  alias Dunda.Scraper
  alias Dunda.Scraper.Normaliser
  alias Dunda.Scraper.Runs

  # Only our own, known sources are accepted (no String.to_atom on the wild).
  @sources %{
    "html" => :html,
    "facebook" => :facebook,
    "instagram" => :instagram,
    "eventbrite" => :eventbrite
  }

  @doc "Enqueue an ingest job from a fetch worker."
  @spec enqueue([map()], String.t(), pos_integer() | nil) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue([], source, org_id) do
    _ = Runs.record(%{organisation_id: org_id, source: source, status: "succeeded", fetched_count: 0, parsed_count: 0, metadata: %{pipeline: "ingest", empty_result: true}})
    {:ok, :nothing_to_ingest}
  end

  def enqueue(raw_events, source, organisation_id) when is_list(raw_events) do
    %{"raw_events" => raw_events, "source" => source, "organisation_id" => organisation_id}
    |> new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"raw_events" => raw, "source" => source} = args}) do
    org_id = args["organisation_id"]

    if Dunda.Containment.blocked?(:dynamic_scraping) do
      {:cancel, :phase_0_containment}
    else
    case Map.fetch(@sources, source) do
      {:ok, source_atom} ->
        normalized = Normaliser.normalise(raw, source_atom, organisation_id: org_id)
        result = normalized |> Enum.map(&Scraper.upsert_event/1) |> tally()
        drift = raw != [] and normalized == []
        if drift do
          Dunda.Observability.increment({:scraper_schema_drift, source})
          Logger.warning("IngestWorker[#{source}] schema drift: all rows rejected")
        end
        _ = record_run(source, org_id, raw, normalized, result, drift)

        Logger.info("IngestWorker[#{source}] org=#{inspect(org_id)} #{inspect(result)}")
        :ok

      :error ->
        Logger.error("IngestWorker: unknown source #{inspect(source)} — discarding job")
        {:cancel, :unknown_source}
    end
    end
  end

  defp tally(results) do
    Enum.reduce(results, %{inserted: 0, updated: 0, duplicate: 0, error: 0}, fn
      {:ok, :inserted, _}, acc -> Map.update!(acc, :inserted, &(&1 + 1))
      {:ok, :updated, _}, acc -> Map.update!(acc, :updated, &(&1 + 1))
      {:skip, :duplicate}, acc -> Map.update!(acc, :duplicate, &(&1 + 1))
      {:error, _}, acc -> Map.update!(acc, :error, &(&1 + 1))
    end)
  end

  defp record_run(source, org_id, raw, normalized, result, drift) do
    attrs = %{organisation_id: org_id, source: source, status: if(drift, do: "schema_drift", else: "succeeded"), finished_at: DateTime.utc_now() |> DateTime.truncate(:second), fetched_count: length(raw), parsed_count: length(normalized), inserted_count: result.inserted, updated_count: result.updated, rejected_count: result.error, schema_drift: drift, metadata: %{pipeline: "ingest"}}
    case Runs.start(Map.put(attrs, :started_at, DateTime.utc_now() |> DateTime.truncate(:second))) do
      {:ok, run} -> Runs.finish(run, attrs)
      _ -> :ok
    end
  rescue
    _ -> :ok
  end
end
