defmodule Dunda.ObservabilityPrometheusTest do
  # async: false — writes to Dunda.Observability's process-global ETS table.
  use ExUnit.Case, async: false

  alias Dunda.Observability

  setup do
    if is_nil(Process.whereis(Observability)), do: Observability.start_link([])
    :ok
  end

  test "render_prometheus/0 formats requests, gauges, and counters as valid-looking Prometheus lines" do
    Observability.observe_request("/prom-test-route", 200, 42_000)
    Observability.increment(:prom_test_counter)
    Observability.gauge(:prom_test_gauge, 7)

    output = Observability.render_prometheus()

    assert output =~ ~r/dunda_requests_total\{route="\/prom-test-route",status="200"\} \d+/
    assert output =~ ~r/dunda_latency_bucket_count\{route="\/prom-test-route",le="\d+"\} \d+/
    assert output =~ "dunda_counter_total{name=\"prom_test_counter\"} 1"
    assert output =~ "dunda_gauge{name=\"prom_test_gauge\"} 7"
    assert output =~ ~r/dunda_oban_queue_depth \d+$/
    refute output =~ "\n\n"
  end

  test "render_prometheus/0 never raises on an empty registry" do
    assert Observability.render_prometheus() =~ "dunda_oban_queue_depth"
  end
end
