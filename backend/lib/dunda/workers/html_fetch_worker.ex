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
    url = opts["url"]
    site = Map.get(@sites, opts["site"], :html)

    case fetch(url) do
      {:ok, body} ->
        body
        |> HtmlScraper.parse(site)
        |> IngestWorker.enqueue("html", org_id)

        :ok

      {:error, :no_url} ->
        {:cancel, :no_url}

      {:error, reason} ->
        Logger.warning("HtmlFetchWorker #{url} failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp fetch(nil), do: {:error, :no_url}
  defp fetch(""), do: {:error, :no_url}

  defp fetch(url) do
    case Req.get(url, max_retries: 0, receive_timeout: 15_000, decode_body: false) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end
end
