defmodule Dunda.Observability do
  @moduledoc "Small dependency-free metrics registry for operational probes."

  use GenServer

  @table :dunda_metrics

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  # Bucket boundaries in milliseconds for the per-route latency histogram.
  # `:infinity` catches anything slower than the largest finite boundary.
  @histogram_buckets_ms [10, 25, 50, 100, 150, 200, 300, 500, 1_000, 2_500, 5_000, :infinity]

  @spec observe_request(String.t(), non_neg_integer(), non_neg_integer()) :: :ok
  def observe_request(route, status, duration_us) do
    update({:requests_total, route, status}, 1)
    update({:request_duration_us_total, route}, duration_us)
    update({:request_duration_count, route}, 1)
    if status >= 500, do: update({:requests_5xx_total, route}, 1)
    update({:latency_bucket, route, latency_bucket_ms(duration_us)}, 1)
    :ok
  end

  @doc "Observes an internal domain-operation latency independently of HTTP routing."
  @spec observe_operation(atom() | String.t(), non_neg_integer()) :: :ok
  def observe_operation(operation, duration_us) do
    update({:operation_latency_bucket, to_string(operation), latency_bucket_ms(duration_us)}, 1)
    :ok
  end

  defp latency_bucket_ms(duration_us) do
    duration_ms = duration_us / 1_000

    Enum.find(@histogram_buckets_ms, :infinity, fn
      :infinity -> true
      boundary -> duration_ms <= boundary
    end)
  end

  @doc """
  Approximate percentile latency (in ms) for `route` from the bucketed
  histogram `observe_request/3` maintains. This is a histogram-bucket
  approximation (returns the smallest bucket boundary containing the
  percentile), not an exact order statistic — adequate for SLO
  pass/fail evaluation, not for precise latency analysis (use real tracing/
  APM for that — see `docs/phase_12_verification_observability_rollout.md`
  § OpenTelemetry tracing). Returns `nil` if the route has no samples.
  """
  @spec latency_percentile(map(), String.t(), number()) :: number() | :infinity | nil
  def latency_percentile(counters, route, percentile) when percentile > 0 and percentile <= 100 do
    buckets =
      counters
      |> Enum.filter(fn {key, _count} -> match?({:latency_bucket, ^route, _boundary}, key) end)
      |> Enum.map(fn {{:latency_bucket, _route, boundary}, count} -> {boundary, count} end)
      |> Enum.sort_by(fn {boundary, _count} ->
        if boundary == :infinity, do: :infinity, else: boundary
      end)

    total = buckets |> Enum.map(&elem(&1, 1)) |> Enum.sum()

    if total == 0 do
      nil
    else
      target = Float.ceil(total * percentile / 100)

      Enum.reduce_while(buckets, 0, fn {boundary, count}, cumulative ->
        new_cumulative = cumulative + count
        if new_cumulative >= target, do: {:halt, boundary}, else: {:cont, new_cumulative}
      end)
    end
  end

  @spec operation_latency_percentile(map(), atom() | String.t(), number()) ::
          number() | :infinity | nil
  def operation_latency_percentile(counters, operation, percentile)
      when percentile > 0 and percentile <= 100 do
    operation = to_string(operation)

    counters
    |> Enum.reduce(%{}, fn
      {{:operation_latency_bucket, ^operation, boundary}, count}, acc ->
        Map.put(acc, {:latency_bucket, operation, boundary}, count)

      _, acc ->
        acc
    end)
    |> latency_percentile(operation, percentile)
  end

  @spec increment(term(), integer()) :: :ok
  def increment(key, amount \\ 1), do: update({:counter, key}, amount)

  @doc """
  Sets a point-in-time value (current overdue-request count, current
  reconciliation-diff count, an "age of oldest pending X" sample) — unlike
  `increment/2`, this overwrites rather than accumulates. Use `increment/2`
  for monotonic totals (things that only ever go up, like requests served);
  use `gauge/2` for anything that can legitimately go back down or represent
  "right now" rather than "since boot".
  """
  @spec gauge(term(), number()) :: :ok
  def gauge(key, value) do
    :ets.insert(@table, {{:gauge, key}, value})
    :ok
  rescue
    ArgumentError -> :ok
  end

  @spec snapshot() :: map()
  def snapshot do
    counters()
    |> Map.new(fn {key, value} -> {inspect(key), value} end)
    |> Map.put("oban_queue_depth", oban_queue_depth())
  end

  @doc """
  Renders every counter/gauge as Prometheus text exposition format
  (`GET /internal/metrics/prometheus`, `DundaWeb.MetricsController.prometheus/2`).

  Before this existed, `/internal/metrics` only returned JSON — no
  Prometheus server could actually scrape this application; the dashboards
  in `infra/observability/dashboards/` and alert rules in
  `infra/observability/alerts/business_invariants.yml` assume THIS endpoint
  as their target, not an external JSON-to-Prometheus adapter (though one
  could still be layered in front for aggregation across nodes).
  """
  @spec render_prometheus() :: String.t()
  def render_prometheus do
    all = counters()

    lines =
      (all
       |> Enum.reject(fn {key, _} ->
         match?({:latency_bucket, _route, _boundary}, key) or
           match?({:operation_latency_bucket, _operation, _boundary}, key)
       end)
       |> Enum.flat_map(&render_metric_line/1)) ++ render_latency_histograms(all)

    (Enum.sort(lines) ++ ["dunda_oban_queue_depth #{oban_queue_depth()}"])
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  defp render_metric_line({{:requests_total, route, status}, count}),
    do: [~s(dunda_requests_total{route="#{escape(route)}",status="#{status}"} #{count})]

  defp render_metric_line({{:requests_5xx_total, route}, count}),
    do: [~s(dunda_requests_5xx_total{route="#{escape(route)}"} #{count})]

  defp render_metric_line({{:request_duration_us_total, route}, total}),
    do: [~s(dunda_request_duration_us_total{route="#{escape(route)}"} #{total})]

  defp render_metric_line({{:request_duration_count, route}, count}),
    do: [~s(dunda_request_duration_count{route="#{escape(route)}"} #{count})]

  defp render_metric_line({{:counter, key}, count}),
    do: [~s(dunda_counter_total{name="#{escape(metric_name(key))}"} #{count})]

  defp render_metric_line({{:gauge, key}, value}),
    do: [~s(dunda_gauge{name="#{escape(metric_name(key))}"} #{value})]

  defp render_metric_line(_other), do: []

  # Prometheus's histogram_quantile() requires CUMULATIVE bucket counts (each
  # `le` bucket includes every smaller bucket), not the raw per-bucket tally
  # `observe_request/3` stores internally — so this is computed at render
  # time per route, not stored pre-cumulated (storing cumulative counts
  # directly would mean every observation writes to N buckets instead of 1).
  defp render_latency_histograms(all) do
    request_entries =
      all
      |> Enum.filter(fn {key, _} -> match?({:latency_bucket, _route, _boundary}, key) end)
      |> Enum.map(fn {{:latency_bucket, route, boundary}, count} -> {route, boundary, count} end)

    operation_entries =
      all
      |> Enum.filter(fn {key, _} ->
        match?({:operation_latency_bucket, _operation, _boundary}, key)
      end)
      |> Enum.map(fn {{:operation_latency_bucket, operation, boundary}, count} ->
        {"operation:#{operation}", boundary, count}
      end)

    (request_entries ++ operation_entries)
    |> Enum.group_by(fn {route, _boundary, _count} -> route end)
    |> Enum.flat_map(fn {route, entries} -> cumulative_bucket_lines(route, entries) end)
  end

  defp cumulative_bucket_lines(route, entries) do
    sorted =
      Enum.sort_by(entries, fn {_route, boundary, _count} ->
        if boundary == :infinity, do: :infinity, else: boundary
      end)

    {lines, _cumulative} =
      Enum.map_reduce(sorted, 0, fn {_route, boundary, count}, cumulative ->
        running = cumulative + count

        {~s(dunda_latency_bucket_count{route="#{escape(route)}",le="#{le_label(boundary)}"} #{running}),
         running}
      end)

    lines
  end

  defp le_label(:infinity), do: "+Inf"
  defp le_label(boundary), do: to_string(boundary)

  defp metric_name(key) when is_atom(key) or is_binary(key), do: to_string(key)
  defp metric_name(key), do: inspect(key)

  defp escape(value) do
    value
    |> to_string()
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
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
    :ets.new(@table, [
      :named_table,
      :public,
      :set,
      read_concurrency: true,
      write_concurrency: true
    ])

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
