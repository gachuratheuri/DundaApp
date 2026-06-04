defmodule Dunda.Workers.FacebookFetchWorker do
  @moduledoc """
  Pulls upcoming events for an organisation's Facebook Page (queue
  `scrape_fetch`) via the Graph API and hands the raw objects to `IngestWorker`.

  Requires `FACEBOOK_GRAPH_TOKEN`. With no token the job cancels cleanly.
  """
  use Oban.Worker, queue: :scrape_fetch, max_attempts: 3

  require Logger

  alias Dunda.Workers.IngestWorker

  @graph_version "v18.0"

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"opts" => %{"page_id" => page_id}} = args}) do
    org_id = args["organisation_id"]

    case token() do
      nil ->
        Logger.info("FacebookFetchWorker: FACEBOOK_GRAPH_TOKEN unset — skipping org #{org_id}")
        {:cancel, :no_credentials}

      token ->
        url = "https://graph.facebook.com/#{@graph_version}/#{page_id}/events"

        case Req.get(url,
               params: [
                 access_token: token,
                 time_filter: "upcoming",
                 fields: "id,name,start_time,place"
               ],
               max_retries: 0,
               receive_timeout: 15_000
             ) do
          {:ok, %{status: 200, body: %{"data" => data}}} when is_list(data) ->
            IngestWorker.enqueue(data, "facebook", org_id)
            :ok

          {:ok, %{status: 200}} ->
            :ok

          {:ok, %{status: status}} ->
            {:error, {:http_status, status}}

          {:error, reason} ->
            Logger.warning("FacebookFetchWorker org #{org_id} failed: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  defp token, do: System.get_env("FACEBOOK_GRAPH_TOKEN")
end
