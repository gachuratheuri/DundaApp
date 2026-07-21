defmodule Dunda.Workers.HtmlFetchWorker do
  @moduledoc """
  Fetches a static/org HTML page (queue `scrape_fetch`), parses it via
  `HtmlScraper.parse/2`, and hands the raw rows to `IngestWorker`.

  Transient HTTP failures return `{:error, _}` so Oban retries with backoff; an
  unparseable page yields `[]` and completes cleanly.
  """
  use Oban.Worker, queue: :scrape_fetch, max_attempts: 3

  require Logger

  alias Dunda.Scraper.HtmlScraper
  alias Dunda.Scraper.SchemaGuard
  alias Dunda.Workers.IngestWorker

  @sites %{
    "ticketsasa" => :ticketsasa,
    "hustlesasa" => :hustlesasa,
    "mookh" => :mookh,
    "kenyabuzz" => :kenyabuzz
  }

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"opts" => opts} = args}) do
    org_id = args["organisation_id"]

    if Dunda.Containment.blocked?(:dynamic_scraping) do
      {:cancel, :phase_0_containment}
    else
      url = opts["url"]
      site = Map.get(@sites, opts["site"], :html)

      case fetch(url) do
        {:ok, body} ->
          rows = HtmlScraper.parse(body, site)
          if rows == [], do: SchemaGuard.report_empty("html", url)
          IngestWorker.enqueue(rows, "html", org_id)

          :ok

        {:error, :no_url} ->
          {:cancel, :no_url}

        {:error, reason} ->
          Logger.warning(
            "HtmlFetchWorker #{Dunda.Security.URL.log_safe(url)} failed: #{inspect(Dunda.Logging.Redactor.redact(reason))}"
          )

          {:error, reason}
      end
    end
  end

  defp fetch(nil), do: {:error, :no_url}
  defp fetch(""), do: {:error, :no_url}

  defp fetch(url) do
    Dunda.Security.URL.fetch(url, receive_timeout: 15_000)
  end
end
