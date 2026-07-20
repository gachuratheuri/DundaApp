defmodule Dunda.ScraperTest do
  use ExUnit.Case, async: true

  alias Dunda.Scraper.Normaliser

  test "normalises a supported HTML row and preserves provenance" do
    [event] =
      Normaliser.normalise(
        [%{"site" => "fixture", "external_id" => "ext-123", "title" => "Test Event", "venue" => "Test Venue", "date_text" => "2026-06-10T14:00:00Z", "price_text" => "KES 1,200", "url" => "https://example.com/events/ext-123"}],
        :html,
        organisation_id: 42
      )

    assert event.name == "Test Event"
    assert event.venue == "Test Venue"
    assert event.price_cents == 120_000
    assert event.source == "html:fixture"
    assert event.external_id == "ext-123"
    assert event.source_url in [nil, "https://example.com/events/ext-123"]
    assert event.organisation_id == 42
  end

  test "provider rows with invalid timestamps are rejected rather than partially persisted" do
    assert Normaliser.normalise([%{"id" => "fb-1", "name" => "Broken", "start_time" => "not-a-date"}], :facebook) == []
  end

  test "generic HTML JSON-LD fixture produces a canonical event" do
    html = ~s(<script type="application/ld+json">{"@type":"Event","@id":"jsonld-1","name":"JSON-LD Night","startDate":"2026-06-10T14:00:00Z","location":{"name":"Venue"}}</script>)
    [row] = Dunda.Scraper.HtmlScraper.parse(html, :html)
    [event] = Normaliser.normalise([row], :html)
    assert event.external_id == "jsonld-1"
    assert event.name == "JSON-LD Night"
    assert event.venue == "Venue"
  end

  test "provider envelope drift is not treated as an empty success" do
    assert {:schema_drift, {:missing_event_collection, "facebook"}} =
             Dunda.Scraper.SchemaGuard.api_events("facebook", %{"items" => []})
  end
end
