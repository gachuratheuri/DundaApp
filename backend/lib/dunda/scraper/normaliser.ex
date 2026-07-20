defmodule Dunda.Scraper.Normaliser do
  @moduledoc """
  Canonicalises heterogeneous raw event maps (from `HtmlScraper.parse/2` or the
  Facebook/Instagram/Eventbrite APIs) into the single shape consumed by
  `Dunda.Events.Event.ingest_changeset/2`.

  Canonical shape:

      %{
        name: String.t(),
        venue: String.t() | nil,
        starts_at: DateTime.t(),
        price_cents: non_neg_integer(),
        capacity: pos_integer(),
        source: String.t(),       # e.g. "html:ticketsasa", "eventbrite"
        external_id: String.t(),
        organisation_id: pos_integer() | nil
      }
  """
  require Logger

  @default_capacity 200

  @doc """
  Normalise a list of raw maps for `html_source`, attaching `organisation_id`
  from `opts`. Invalid rows are dropped (and logged), never raised — one bad
  record must not poison the ingest batch.
  """
  @spec normalise([map()], atom(), keyword()) :: [map()]
  def normalise(raw_events, html_source, opts \\ []) when is_list(raw_events) do
    org_id = Keyword.get(opts, :organisation_id)

    raw_events
    |> Enum.map(&do_normalise(&1, html_source))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&Map.put(&1, :organisation_id, org_id))
  end

  # ── HTML sites share one raw shape (title/venue/date_text/price_text) ────────
  # Step 3 of the contract: a new HTML site only needs its atom added here.
  defp do_normalise(raw, html_source)
       when html_source in [:html, :ticketsasa, :hustlesasa, :mookh, :kenyabuzz] do
    with {:ok, starts_at} <- parse_datetime(raw["date_text"]),
         name when is_binary(name) and name != "" <- raw["title"] do
      %{
        name: name,
        venue: raw["venue"] || "TBA",
        starts_at: starts_at,
        price_cents: parse_price_cents(raw["price_text"]),
        capacity: @default_capacity,
        source: "html:#{raw["site"] || html_source}",
        external_id: to_string(raw["external_id"]),
        source_url: safe_source_url(raw["url"])
      }
    else
      _ ->
        Logger.debug("Normaliser: dropped unparseable html row: #{inspect(raw)}")
        nil
    end
  end

  # ── Eventbrite API event object ──────────────────────────────────────────────
  defp do_normalise(%{"id" => id, "name" => %{"text" => name}} = ev, :eventbrite) do
    with {:ok, starts_at, _} <- DateTime.from_iso8601(get_in(ev, ["start", "utc"]) || "") do
      %{
        name: name,
        venue: get_in(ev, ["venue", "name"]) || "TBA",
        starts_at: DateTime.truncate(starts_at, :second),
        price_cents: 0,
        capacity: ev["capacity"] || @default_capacity,
        source: "eventbrite",
        external_id: to_string(id),
        source_url: safe_source_url(ev["url"] || get_in(ev, ["url", "html"]))
      }
    else
      _ -> nil
    end
  end

  # ── Facebook + Instagram Graph API events share a shape ──────────────────────
  defp do_normalise(%{"id" => id, "name" => name} = ev, source)
       when source in [:facebook, :instagram] do
    with start_time when is_binary(start_time) <- ev["start_time"],
         {:ok, starts_at, _} <- DateTime.from_iso8601(start_time) do
      %{
        name: name,
        venue: get_in(ev, ["place", "name"]) || "TBA",
        starts_at: DateTime.truncate(starts_at, :second),
        price_cents: 0,
        capacity: @default_capacity,
        source: to_string(source),
        external_id: to_string(id),
        source_url: safe_source_url(ev["permalink"] || ev["url"])
      }
    else
      _ -> nil
    end
  end

  defp do_normalise(raw, html_source) do
    Logger.warning("Normaliser: no clause for source #{inspect(html_source)}: #{inspect(raw)}")
    nil
  end

  # ── Parsing helpers ──────────────────────────────────────────────────────────

  defp parse_datetime(nil), do: :error

  defp parse_datetime(text) when is_binary(text) do
    case DateTime.from_iso8601(text) do
      {:ok, dt, _} -> {:ok, DateTime.truncate(dt, :second)}
      _ -> parse_date_only(text)
    end
  end

  # Fallback: accept a bare "YYYY-MM-DD" and assume 19:00 EAT (16:00 UTC).
  defp parse_date_only(text) do
    case Regex.run(~r/(\d{4})-(\d{2})-(\d{2})/, text) do
      [_, y, m, d] ->
        {:ok,
         DateTime.new!(Date.new!(int(y), int(m), int(d)), Time.new!(16, 0, 0), "Etc/UTC")
         |> DateTime.truncate(:second)}

      _ ->
        :error
    end
  end

  defp parse_price_cents(nil), do: 0

  defp parse_price_cents(text) when is_binary(text) do
    case Regex.run(~r/(\d[\d,]*)/, text) do
      [_, digits] -> digits |> String.replace(",", "") |> int() |> Kernel.*(100)
      _ -> 0
    end
  end

  defp int(s), do: String.to_integer(s)

  defp safe_source_url(url) when is_binary(url) do
    url = String.trim(url)
    if Dunda.Security.URL.safe_https_url?(url), do: url, else: nil
  end
  defp safe_source_url(_), do: nil
end
