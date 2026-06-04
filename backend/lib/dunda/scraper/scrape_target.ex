defmodule Dunda.Scraper.ScrapeTarget do
  @moduledoc """
  Describes one place the scraper should pull events from.

  ## The 3-step contract for adding a source

    1. Add a `%ScrapeTarget{}` here (or `HtmlScraper.targets/0` for static sites).
    2. Add a `parse/2` clause in `Dunda.Scraper.HtmlScraper` for the `:source`.
    3. Add a `do_normalise/2` clause (or extend the existing guard) in
       `Dunda.Scraper.Normaliser`.

  None of the three requires a restart — workers read these at job time.
  """

  @enforce_keys [:source]
  defstruct source: nil,
            url: nil,
            # Worker module responsible for fetching this target.
            fetcher: nil,
            # Tenant this target belongs to (nil for global/public targets).
            organisation_id: nil,
            # Free-form per-source config (api ids, tokens key, selectors…).
            opts: %{}

  @type source :: :facebook | :instagram | :eventbrite | :html

  @type t :: %__MODULE__{
          source: source(),
          url: String.t() | nil,
          fetcher: module() | nil,
          organisation_id: pos_integer() | nil,
          opts: map()
        }
end
