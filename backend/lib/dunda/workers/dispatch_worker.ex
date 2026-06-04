defmodule Dunda.Workers.DispatchWorker do
  @moduledoc """
  Serialised cron fan-out (queue `scrape_dispatch`, concurrency 1).

  On every tick it reads the live `organisations` table plus the static
  `HtmlScraper.targets/0`, turns each connected source into a fetch job, and
  bulk-inserts them. Because the org rows ARE the configuration, saving new IDs
  in the Organiser Portal changes what gets dispatched with no deploy/restart.
  The portal also enqueues this worker immediately on save for fast turnaround.
  """
  use Oban.Worker, queue: :scrape_dispatch, max_attempts: 3

  require Logger

  alias Dunda.Organisations
  alias Dunda.Scraper.{HtmlScraper, ScrapeTarget}

  alias Dunda.Workers.{
    EventbriteFetchWorker,
    FacebookFetchWorker,
    HtmlFetchWorker,
    InstagramFetchWorker
  }

  @impl Oban.Worker
  def perform(_job) do
    jobs = dispatch_jobs()
    {count, _} = Oban.insert_all(jobs) |> tally()
    Logger.info("DispatchWorker fanned out #{count} fetch jobs")
    {:ok, count}
  end

  @doc "All fetch jobs for this tick: org-configured targets + static HTML targets."
  @spec dispatch_jobs() :: [Ecto.Changeset.t()]
  def dispatch_jobs do
    (dynamic_targets_from_orgs() ++ HtmlScraper.targets())
    |> Enum.map(&to_job/1)
  end

  @doc """
  Build a `%ScrapeTarget{}` per connected source across all scraper-enabled
  organisations. A nil/blank source id is skipped; `scraper_enabled = false`
  orgs are never returned by `Organisations.scrapable_organisations/0`.
  """
  @spec dynamic_targets_from_orgs() :: [ScrapeTarget.t()]
  def dynamic_targets_from_orgs do
    Organisations.scrapable_organisations()
    |> Enum.flat_map(&org_targets/1)
  end

  defp org_targets(org) do
    [
      target(org.facebook_page_id, :facebook, FacebookFetchWorker, org.id, %{
        "page_id" => org.facebook_page_id
      }),
      target(org.instagram_account_id, :instagram, InstagramFetchWorker, org.id, %{
        "account_id" => org.instagram_account_id
      }),
      target(org.eventbrite_org_id, :eventbrite, EventbriteFetchWorker, org.id, %{
        "eventbrite_org_id" => org.eventbrite_org_id
      }),
      target(org.html_scrape_url, :html, HtmlFetchWorker, org.id, %{"site" => "org_#{org.id}"})
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp target(blank, _source, _fetcher, _org_id, _opts) when blank in [nil, ""], do: nil

  defp target(id, source, fetcher, org_id, opts) do
    url = if source == :html, do: id, else: nil
    %ScrapeTarget{source: source, url: url, fetcher: fetcher, organisation_id: org_id, opts: opts}
  end

  defp to_job(%ScrapeTarget{fetcher: fetcher, organisation_id: org_id, opts: opts, url: url}) do
    args = %{
      "organisation_id" => org_id,
      "opts" => Map.put(opts, "url", url)
    }

    fetcher.new(args)
  end

  defp tally({:ok, jobs}) when is_list(jobs), do: {length(jobs), jobs}
  defp tally(jobs) when is_list(jobs), do: {length(jobs), jobs}
  defp tally(other), do: {0, other}
end
