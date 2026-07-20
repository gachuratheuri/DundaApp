defmodule Dunda.Observability do
  @moduledoc """Small dependency-free metrics registry for operational probes."""

  use GenServer

  @table :dunda_metrics

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @spec observe_request(String.t(), non_neg_integer(), non_neg_integer()) :: :ok
  def observe_request(route, status, duration_us) do
    update({:requests_total, route, status}, 1)
    update({:request_duration_us_total, route}, duration_us)
    update({:request_duration_count, route}, 1)
    if status >= 500, do: update({:requests_5xx_total, route}, 1)
    :ok
  end

  @spec increment(term(), integer()) :: :ok
  def increment(key, amount \\ 1), do: update({:counter, key}, amount)

  @spec snapshot() :: map()
  def snapshot do
    counters()
    |> Map.new(fn {key, value} -> {inspect(key), value} end)
    |> Map.put("oban_queue_depth", oban_queue_depth())
  end

  @doc "Returns raw, structured counters for deterministic SLO evaluation."
  @spec counters() :: map()
  def counters do
    @table
    |> :ets.tab2list()
    |> Map.new()
  rescue
    ArgumentError -> %{}
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true, write_concurrency: true])
    {:ok, %{}}
  end

  defp update(key, amount) do
    :ets.update_counter(@table, key, {2, amount}, {key, 0})
  rescue
    ArgumentError -> :ok
  end

  # The HPA consumes this as an external metric. A missing Oban table or a
  # transient database failure is represented as zero only for telemetry; it
  # never changes job state or checkout authority.
  defp oban_queue_depth do
    case Ecto.Adapters.SQL.query(
           Dunda.Repo,
           "SELECT COUNT(*) FROM oban_jobs WHERE state IN ('available', 'executing', 'retryable')",
           [],
           timeout: 1_000
         ) do
      {:ok, %{rows: [[count]]}} when is_integer(count) -> count
      _ -> 0
    end
  rescue
    _ -> 0
  end
end
