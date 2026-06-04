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

  # Only our own, known sources are accepted (no String.to_atom on the wild).
  @sources %{
    "html" => :html,
    "facebook" => :facebook,
    "instagram" => :instagram,
    "eventbrite" => :eventbrite
  }

  @doc "Enqueue an ingest job from a fetch worker."
  @spec enqueue([map()], String.t(), pos_integer() | nil) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue([], _source, _org_id), do: {:ok, :nothing_to_ingest}

  def enqueue(raw_events, source, organisation_id) when is_list(raw_events) do
    %{"raw_events" => raw_events, "source" => source, "organisation_id" => organisation_id}
    |> new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"raw_events" => raw, "source" => source} = args}) do
    org_id = args["organisation_id"]

    case Map.fetch(@sources, source) do
      {:ok, source_atom} ->
        result =
          raw
          |> Normaliser.normalise(source_atom, organisation_id: org_id)
          |> Enum.map(&Scraper.upsert_event/1)
          |> tally()

        Logger.info("IngestWorker[#{source}] org=#{inspect(org_id)} #{inspect(result)}")
        :ok

      :error ->
        Logger.error("IngestWorker: unknown source #{inspect(source)} — discarding job")
        {:cancel, :unknown_source}
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
end
