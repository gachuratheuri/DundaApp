defmodule Dunda.Scraper.SchemaGuard do
  @moduledoc "Rejects structurally changed provider responses before ingestion."
  require Logger

  def api_events(source, %{"events" => events}) when source == "eventbrite" and is_list(events), do: {:ok, events}
  def api_events(source, %{"data" => data}) when source in ["facebook", "instagram"] and is_list(data), do: {:ok, data}
  def api_events(source, _), do: {:schema_drift, {:missing_event_collection, source}}

  def report_empty(source, target) do
    Dunda.Observability.increment({:scraper_empty_result, source})
    Logger.warning("scraper source returned zero events source=#{source} target=#{inspect(target)}")
    :ok
  end
end
