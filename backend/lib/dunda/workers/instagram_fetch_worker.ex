defmodule Dunda.Workers.InstagramFetchWorker do
  @moduledoc """
  Pulls recent media for an organisation's Instagram Business account (queue
  `scrape_fetch`) via the Graph API. Captions are treated as event posts and
  reshaped to the shared Facebook/Instagram raw shape before being handed to
  `IngestWorker`.

  Requires `INSTAGRAM_GRAPH_TOKEN`. With no token the job cancels cleanly.
  """
  use Oban.Worker, queue: :scrape_fetch, max_attempts: 3

  require Logger

  alias Dunda.Workers.IngestWorker

  @graph_version "v18.0"

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"opts" => %{"account_id" => account_id}} = args}) do
    org_id = args["organisation_id"]

    case token() do
      nil ->
        Logger.info("InstagramFetchWorker: INSTAGRAM_GRAPH_TOKEN unset — skipping org #{org_id}")
        {:cancel, :no_credentials}

      token ->
        url = "https://graph.facebook.com/#{@graph_version}/#{account_id}/media"

        case Req.get(url,
               params: [access_token: token, fields: "id,caption,timestamp,permalink"],
               max_retries: 0,
               receive_timeout: 15_000
             ) do
          {:ok, %{status: 200, body: %{"data" => data}}} when is_list(data) ->
            data |> Enum.map(&to_event_shape/1) |> IngestWorker.enqueue("instagram", org_id)
            :ok

          {:ok, %{status: 200}} ->
            :ok

          {:ok, %{status: status}} ->
            {:error, {:http_status, status}}

          {:error, reason} ->
            Logger.warning("InstagramFetchWorker org #{org_id} failed: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  # Reshape an IG media object into the shared FB/IG raw shape the Normaliser
  # expects (id/name/start_time/place).
  defp to_event_shape(media) do
    %{
      "id" => media["id"],
      "name" => media["caption"] |> to_string() |> String.slice(0, 120),
      "start_time" => media["timestamp"],
      "place" => nil
    }
  end

  defp token, do: System.get_env("INSTAGRAM_GRAPH_TOKEN")
end
