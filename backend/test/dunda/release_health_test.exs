defmodule Dunda.ReleaseHealthTest do
  use ExUnit.Case, async: true

  alias Dunda.ReleaseHealth

  defp endpoint_evidence do
    %{
      {:latency_bucket, "/api/checkout", 100} => 100,
      {:operation_latency_bucket, "inventory_reservation", 50} => 100,
      {:gauge, :webhook_ack_ms_last} => 100
    }
  end

  test "passes when error and average latency remain within thresholds" do
    report =
      ReleaseHealth.evaluate(
        Map.merge(endpoint_evidence(), %{
          {:requests_total, "/api/events", 200} => 99,
          {:requests_total, "/api/events", 500} => 1,
          {:request_duration_us_total, "/api/events"} => 100_000,
          {:request_duration_count, "/api/events"} => 100
        })
      )

    assert report.healthy
    assert report.requests == 100
    assert report.errors_5xx == 1
    assert report.average_latency_us == 1_000
  end

  test "fails when either SLO threshold is exceeded" do
    report =
      ReleaseHealth.evaluate(
        Map.merge(endpoint_evidence(), %{
          {:requests_total, "/api/events", 200} => 1,
          {:requests_total, "/api/events", 500} => 1,
          {:request_duration_us_total, "/api/events"} => 1_000_000,
          {:request_duration_count, "/api/events"} => 1
        })
      )

    refute report.healthy
    assert report.error_rate == 0.5
    assert report.average_latency_us == 1_000_000
  end

  test "absence of endpoint evidence fails the release gate" do
    report = ReleaseHealth.evaluate(%{})

    refute report.healthy
    assert report.requests == 0
    assert is_nil(report.average_latency_us)
  end
end
