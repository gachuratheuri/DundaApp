defmodule Dunda.ScraperTest do
  use Dunda.DataCase

  alias Dunda.Scraper

  describe "normaliser" do
    test "normalises external scraper payload into Event struct" do
      payload = %{
        "external_id" => "ext-123",
        "title" => "Test Event",
        "start_time" => "2026-06-10T14:00:00Z",
        "venue_name" => "Test Venue",
        "ticket_url" => "https://example.com/tickets"
      }

      assert {:ok, event} = Scraper.normalise(payload)
      assert event.name == "Test Event"
      assert event.venue == "Test Venue"
      assert event.scraper_source == "external"
    end
  end
end
