defmodule Dunda.Workers.EventbriteFetchWorker do
  @moduledoc """
  Pulls live events for an organisation's Eventbrite org id (queue
  `scrape_fetch`) and hands the raw API objects to `IngestWorker`.

  Requires `EVENTBRITE_TOKEN`. With no token the job cancels cleanly rather than
  retrying forever — useful in dev where the source isn't wired.
  """
  use Oban.Worker, queue: :scrape_fetch, max_attempts: 3

  require Logger

  alias Dunda.Workers.IngestWorker

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"opts" => %{"eventbrite_org_id" => ebo_id}} = args}) do
    org_id = args["organisation_id"]

    case token() do
      nil ->
        Logger.info("EventbriteFetchWorker: EVENTBRITE_TOKEN unset — skipping org #{org_id}")
        {:cancel, :no_credentials}

      token ->
        url = "https://www.eventbriteapi.com/v3/organizations/#{ebo_id}/events/"

        case Req.get(url,
               params: [status: "live", expand: "venue"],
               auth: {:bearer, token},
               max_retries: 0,
               receive_timeout: 15_000
             ) do
          {:ok, %{status: 200, body: %{"events" => events}}} when is_list(events) ->
            IngestWorker.enqueue(events, "eventbrite", org_id)
            :ok

          {:ok, %{status: 200}} ->
            :ok

          {:ok, %{status: status}} ->
            {:error, {:http_status, status}}

          {:error, reason} ->
            Logger.warning("EventbriteFetchWorker org #{org_id} failed: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  defp token, do: System.get_env("EVENTBRITE_TOKEN")
end
