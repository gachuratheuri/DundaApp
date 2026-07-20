defmodule Dunda.ReleaseHealth do
  @moduledoc """
  Deterministic post-release SLO evaluation.

  This module is deliberately read-only.  It evaluates counters local to the
  current node and therefore produces evidence for an operator or an external
  metrics system; it never revokes approvals or changes containment itself.
  """

  @default_error_rate 0.01
  @default_average_latency_us 500_000

  @type report :: %{
          healthy: boolean(),
          requests: non_neg_integer(),
          errors_5xx: non_neg_integer(),
          error_rate: float(),
          average_latency_us: non_neg_integer() | nil,
          thresholds: %{error_rate_max: float(), average_latency_us_max: non_neg_integer()}
        }

  @spec evaluate() :: report()
  @spec evaluate(map()) :: report()
  def evaluate(counters \\ Dunda.Observability.counters()) when is_map(counters) do
    {requests, errors_5xx} = request_totals(counters)
    {duration_us, duration_count} = duration_totals(counters)
    error_rate = if requests == 0, do: 0.0, else: errors_5xx / requests
    average_latency_us = if duration_count == 0, do: nil, else: div(duration_us, duration_count)
    thresholds = thresholds()

    %{
      healthy:
        error_rate <= thresholds.error_rate_max and
          (is_nil(average_latency_us) or average_latency_us <= thresholds.average_latency_us_max),
      requests: requests,
      errors_5xx: errors_5xx,
      error_rate: Float.round(error_rate, 6),
      average_latency_us: average_latency_us,
      thresholds: thresholds
    }
  rescue
    _ ->
      %{healthy: false, requests: 0, errors_5xx: 0, error_rate: 1.0, average_latency_us: nil, thresholds: thresholds()}
  end

  @spec thresholds() :: %{error_rate_max: float(), average_latency_us_max: non_neg_integer()}
  def thresholds do
    configured = Application.get_env(:dunda, :phase5_slo, [])

    %{
      error_rate_max:
        Keyword.get(configured, :error_rate_max)
        |> bounded_error_rate(),
      average_latency_us_max:
        numeric_or_default(Keyword.get(configured, :average_latency_us_max), @default_average_latency_us)
        |> trunc()
        |> max(1)
    }
  rescue
    _ -> %{error_rate_max: @default_error_rate, average_latency_us_max: @default_average_latency_us}
  end

  defp request_totals(counters) do
    Enum.reduce(counters, {0, 0}, fn
      {{:requests_total, _route, status}, count}, {requests, errors} when is_integer(status) ->
        {requests + max(count, 0), errors + if(status >= 500, do: max(count, 0), else: 0)}

      _, acc -> acc
    end)
  end

  defp duration_totals(counters) do
    Enum.reduce(counters, {0, 0}, fn
      {{:request_duration_us_total, _route}, total}, {duration, count} ->
        {duration + max(total, 0), count}

      {{:request_duration_count, _route}, route_count}, {duration, count} ->
        {duration, count + max(route_count, 0)}

      _, acc -> acc
    end)
  end

  defp numeric_or_default(value, _default) when is_integer(value) or is_float(value), do: value
  defp numeric_or_default(_, default), do: default

  defp bounded_error_rate(value) when is_integer(value) or is_float(value) do
    value = value * 1.0
    if value >= 0.0 and value <= 1.0, do: value, else: @default_error_rate
  end

  defp bounded_error_rate(_), do: @default_error_rate
end
