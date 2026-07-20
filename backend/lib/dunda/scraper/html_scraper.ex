defmodule Dunda.Scraper.HtmlScraper do
  @moduledoc """
  Owns the catalogue of static HTML targets (`targets/0`) and the per-site CSS
  selector clauses (`parse/2`) that turn raw HTML into a list of raw event maps.

  Raw maps produced here are intentionally un-normalised — shape varies per
  site. `Dunda.Scraper.Normaliser` is responsible for canonicalising them.
  """
  require Logger

  alias Dunda.Scraper.ScrapeTarget

  @doc """
  Static, always-on HTML targets (public listings not tied to an org).

  ### Step 1 of the add-a-source contract — append a `%ScrapeTarget{}` here.
  """
  @spec targets() :: [ScrapeTarget.t()]
  def targets do
    [
      %ScrapeTarget{
        source: :html,
        url: "https://www.ticketsasa.com/events",
        fetcher: Dunda.Workers.HtmlFetchWorker,
        opts: %{"site" => "ticketsasa"}
      },
      %ScrapeTarget{
        source: :html,
        url: "https://hustlesasa.com/discover/events",
        fetcher: Dunda.Workers.HtmlFetchWorker,
        opts: %{"site" => "hustlesasa"}
      },
      %ScrapeTarget{
        source: :html,
        url: "https://mookh.com/events",
        fetcher: Dunda.Workers.HtmlFetchWorker,
        opts: %{"site" => "mookh"}
      },
      %ScrapeTarget{
        source: :html,
        url: "https://www.kenyabuzz.com/events",
        fetcher: Dunda.Workers.HtmlFetchWorker,
        opts: %{"site" => "kenyabuzz"}
      }
    ]
  end

  @doc """
  Parse a raw HTML body into a list of raw event maps for a given `site`.

  ### Step 2 of the add-a-source contract — add a clause matching the site atom.
  Returns `[]` (and logs) for unknown sites or unparseable HTML so a single bad
  page never crashes the fetch queue.
  """
  @spec parse(binary(), atom()) :: [map()]
  def parse(html, site) when is_binary(html) do
    case Floki.parse_document(html) do
      {:ok, doc} -> do_parse(doc, site)
      {:error, reason} ->
        Logger.warning("HtmlScraper: failed to parse #{site} document: #{inspect(reason)}")
        []
    end
  end

  def parse(_html, _site), do: []

  # ── Per-site selector clauses ───────────────────────────────────────────────

  defp do_parse(doc, :ticketsasa) do
    doc
    |> Floki.find(".event-card")
    |> Enum.map(fn card ->
      %{
        "site" => "ticketsasa",
        "external_id" => card |> Floki.attribute("data-event-id") |> first(),
        "title" => card |> Floki.find(".event-title") |> Floki.text() |> clean(),
        "venue" => card |> Floki.find(".event-venue") |> Floki.text() |> clean(),
        "date_text" => card |> Floki.find(".event-date") |> Floki.text() |> clean(),
        "price_text" => card |> Floki.find(".event-price") |> Floki.text() |> clean(),
        "url" => card |> Floki.find("a") |> Floki.attribute("href") |> first()
      }
    end)
    |> Enum.reject(&blank_id?/1)
  end

  defp do_parse(doc, :hustlesasa) do
    doc
    |> Floki.find("article.product-card")
    |> Enum.map(fn card ->
      %{
        "site" => "hustlesasa",
        "external_id" => card |> Floki.attribute("id") |> first(),
        "title" => card |> Floki.find("h3") |> Floki.text() |> clean(),
        "venue" => card |> Floki.find(".location") |> Floki.text() |> clean(),
        "date_text" => card |> Floki.find("time") |> Floki.attribute("datetime") |> first(),
        "price_text" => card |> Floki.find(".price") |> Floki.text() |> clean(),
        "url" => card |> Floki.find("a.cta") |> Floki.attribute("href") |> first()
      }
    end)
    |> Enum.reject(&blank_id?/1)
  end

  defp do_parse(doc, :mookh) do
    doc
    |> Floki.find("[data-event-id], .event-listing-card")
    |> Enum.map(fn card ->
      %{
        "site" => "mookh",
        "external_id" =>
          card |> Floki.attribute("data-event-id") |> first() ||
            card |> Floki.find("a") |> Floki.attribute("href") |> first(),
        "title" => card |> Floki.find(".event-name, h2, h3") |> Floki.text() |> clean(),
        "venue" => card |> Floki.find(".event-location, .venue") |> Floki.text() |> clean(),
        "date_text" =>
          card |> Floki.find("time") |> Floki.attribute("datetime") |> first() ||
            card |> Floki.find(".event-date, .date") |> Floki.text() |> clean(),
        "price_text" => card |> Floki.find(".event-price, .price, .from-price") |> Floki.text() |> clean(),
        "url" => card |> Floki.find("a") |> Floki.attribute("href") |> first()
      }
    end)
    |> Enum.reject(&blank_id?/1)
  end

  defp do_parse(doc, :kenyabuzz) do
    doc
    |> Floki.find(".event-item, article.event")
    |> Enum.map(fn card ->
      %{
        "site" => "kenyabuzz",
        "external_id" =>
          card |> Floki.attribute("data-id") |> first() ||
            card |> Floki.find("a") |> Floki.attribute("href") |> first(),
        "title" => card |> Floki.find(".event-title, h2, h3") |> Floki.text() |> clean(),
        "venue" => card |> Floki.find(".event-venue, .location") |> Floki.text() |> clean(),
        "date_text" =>
          card |> Floki.find("time") |> Floki.attribute("datetime") |> first() ||
            card |> Floki.find(".event-date, .date") |> Floki.text() |> clean(),
        "price_text" => card |> Floki.find(".event-price, .price, .ticket-price") |> Floki.text() |> clean(),
        "url" => card |> Floki.find("a") |> Floki.attribute("href") |> first()
      }
    end)
    |> Enum.reject(&blank_id?/1)
  end

  # Generic, standards-based fallback for organiser-approved pages. It only
  # consumes schema.org Event JSON-LD; arbitrary page text is never executed
  # or interpreted as code.
  defp do_parse(doc, :html) do
    doc
    |> Floki.find("script[type=\"application/ld+json\"]")
    |> Enum.flat_map(fn script ->
      case Jason.decode(Floki.text(script)) do
        {:ok, value} when is_map(value) -> [value]
        {:ok, values} when is_list(values) -> values
        _ -> []
      end
    end)
    |> Enum.filter(fn event -> event["@type"] in ["Event", ["Event"]] end)
    |> Enum.map(fn event ->
      location = event["location"] || %{}
      %{
        "site" => "jsonld",
        "external_id" => jsonld_id(event),
        "title" => event["name"],
        "venue" => location["name"],
        "date_text" => event["startDate"],
        "price_text" => get_in(event, ["offers", "price"]),
        "url" => event["url"]
      }
    end)
    |> Enum.reject(&blank_id?/1)
  end

  defp do_parse(_doc, site) do
    Logger.warning("HtmlScraper: no parse/2 clause for site #{inspect(site)}")
    []
  end

  # ── Helpers ─────────────────────────────────────────────────────────────────

  defp first([value | _]), do: value
  defp first(_), do: nil

  defp jsonld_id(event) do
    event["@id"] || event["url"] ||
      (:crypto.hash(:sha256, to_string(event["name"]) <> to_string(event["startDate"]))
       |> Base.encode16(case: :lower))
  end

  defp clean(nil), do: nil
  defp clean(text), do: text |> String.trim() |> String.replace(~r/\s+/, " ")

  defp blank_id?(%{"external_id" => id}), do: is_nil(id) or id == ""
end
