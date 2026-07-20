defmodule Dunda.ObservabilityTest do
  use ExUnit.Case, async: false

  setup do
    if is_nil(Process.whereis(Dunda.Observability)), do: Dunda.Observability.start_link([])
    :ok
  end

  test "records bounded request counters and durations" do
    assert :ok = Dunda.Observability.observe_request("/api/events", 200, 42)
    assert :ok = Dunda.Observability.observe_request("/api/events", 500, 58)
    metrics = Dunda.Observability.snapshot()

    assert metrics["{:requests_total, \"/api/events\", 200}"] >= 1
    assert metrics["{:requests_5xx_total, \"/api/events\"}"] >= 1
    assert metrics["{:request_duration_us_total, \"/api/events\"}"] >= 100
  end
end
