defmodule Dunda.ReleaseHealthEndpointSloTest do
  @moduledoc """
  Tests the Phase 12 per-endpoint p95/p99 SLO evaluation added to
  `Dunda.ReleaseHealth.evaluate/1` — additive to the existing global
  error-rate/average-latency check (`test/dunda/release_health_test.exs`
  covers that path and is unaffected by this addition).
  """
  # async: false to match test/dunda/observability_test.exs's convention —
  # the last test in this module writes to Dunda.Observability's
  # process-global ETS table.
  use ExUnit.Case, async: false

  alias Dunda.Observability
  alias Dunda.ReleaseHealth

  test "latency_percentile/3 approximates p95/p99 from the bucketed histogram" do
    counters = %{
      {:latency_bucket, "/api/checkout", 100} => 95,
      {:latency_bucket, "/api/checkout", 500} => 5
    }

    assert Observability.latency_percentile(counters, "/api/checkout", 95) == 100
    assert Observability.latency_percentile(counters, "/api/checkout", 99) == 500
    assert Observability.latency_percentile(counters, "/api/checkout", 50) == 100
  end

  test "latency_percentile/3 returns nil for a route with no samples" do
    assert Observability.latency_percentile(%{}, "/api/checkout", 95) == nil
  end

  test "checkout p95 breach marks the report unhealthy even when global averages are fine" do
    counters = %{
      {:requests_total, "/api/checkout", 200} => 100,
      {:request_duration_us_total, "/api/checkout"} => 100_000,
      {:request_duration_count, "/api/checkout"} => 100,
      # 95 fast requests, 5 requests over the 300ms p95 SLO.
      {:latency_bucket, "/api/checkout", 100} => 95,
      {:latency_bucket, "/api/checkout", 500} => 5
    }

    report = ReleaseHealth.evaluate(counters)

    refute report.endpoint_slo.checkout_p95_ok
    refute report.healthy
  end

  test "checkout p95 within bounds keeps the report healthy" do
    counters = %{
      {:latency_bucket, "/api/checkout", 100} => 100
    }

    report = ReleaseHealth.evaluate(counters)
    assert report.endpoint_slo.checkout_p95_ok
    assert report.endpoint_slo.checkout_p95_ms == 100
    assert report.healthy
  end

  test "a webhook_ack_ms_last gauge over the 2s threshold breaches its SLO" do
    counters = %{{:gauge, :webhook_ack_ms_last} => 2_500}
    report = ReleaseHealth.evaluate(counters)

    refute report.endpoint_slo.webhook_ack_ok
    refute report.healthy
  end

  test "Observability.observe_request/3 populates the latency histogram" do
    Observability.observe_request("/api/checkout-histogram-test", 200, 50_000)
    counters = Observability.counters()
    assert Map.get(counters, {:latency_bucket, "/api/checkout-histogram-test", 50}) == 1
  end
end
