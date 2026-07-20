defmodule Mix.Tasks.Dunda.LoadTest do
  use Mix.Task
  @shortdoc "In-process load generator against the inventory reservation path"

  @moduledoc """
  Fires many concurrent `Dunda.Checkout.create_payment_intent/2` calls — the
  real reservation transaction (`Dunda.Checkout.reserve_from_quote!/4`'s
  guarded `Repo.update_all` on `inventory_pools`), not a reimplementation —
  against one event with abundant capacity (so requests succeed rather than
  hitting `:inventory_unavailable`, keeping this a *latency* measurement,
  not a second oversell test — that's `test/dunda/inventory_property_test.exs`
  and `test/dunda/inventory_test.exs`), and reports p50/p95/p99 latency and
  achieved throughput against the root plan's numeric SLO: reservation p99
  below 150ms.

  Quote creation is unmeasured setup (one quote per request, since a quote
  is single-use); only `create_payment_intent/2` — the reservation itself —
  is timed, so this isolates the reservation transaction's latency from
  quote-signing overhead.

      mix dunda.load_test --requests 500 --concurrency 50

  This complements, and does not replace, `test/dunda/inventory_test.exs`'s
  50-way *correctness*-under-contention test — this is a throughput/latency
  measurement at a configurable, much larger scale (the root plan's
  "2-5x forecast peak" target), not a pass/fail oversell assertion (though it
  does assert p99 against the SLO). A true multi-node soak/chaos run against
  a live cluster remains external evidence — see
  `docs/phase_12_verification_observability_rollout.md`.
  """

  alias Dunda.Checkout
  alias Dunda.Events

  @p99_threshold_ms 150

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    Application.put_env(:dunda, :containment_mode, false)

    {opts, _, _} =
      OptionParser.parse(args, switches: [requests: :integer, concurrency: :integer])

    requests = opts[:requests] || 500
    concurrency = opts[:concurrency] || 50

    Mix.shell().info("Setting up #{requests} quotes against a high-capacity pool...")
    user = setup_user!()
    event = setup_event!(requests)

    quotes =
      1..requests
      |> Enum.map(fn _ ->
        {:ok, quote} = Checkout.create_quote(user.id, %{event_id: event.id, quantity: 1})
        quote
      end)

    Mix.shell().info("Firing #{requests} reservation requests at concurrency #{concurrency}...")

    {wall_us, results} =
      :timer.tc(fn ->
        quotes
        |> Task.async_stream(&time_reservation(user.id, &1), max_concurrency: concurrency, timeout: 30_000)
        |> Enum.map(fn {:ok, result} -> result end)
      end)

    successes = Enum.count(results, &match?({:ok, _us}, &1))
    latencies_us = results |> Enum.filter(&match?({:ok, _us}, &1)) |> Enum.map(&elem(&1, 1)) |> Enum.sort()

    report(requests, successes, latencies_us, wall_us)
  end

  defp time_reservation(user_id, quote) do
    key = Base.encode16(:crypto.strong_rand_bytes(10))
    started = System.monotonic_time(:microsecond)

    case Checkout.create_payment_intent(user_id, %{quote_id: quote.id, idempotency_key: key, phone: "254712345678"}) do
      {:ok, _intent} -> {:ok, System.monotonic_time(:microsecond) - started}
      {:error, reason} -> {:error, reason}
    end
  end

  defp report(requests, successes, latencies_us, wall_us) do
    p50 = percentile(latencies_us, 50)
    p95 = percentile(latencies_us, 95)
    p99 = percentile(latencies_us, 99)
    throughput = if wall_us > 0, do: Float.round(requests * 1_000_000 / wall_us, 1), else: 0.0

    Mix.shell().info("""

    Requests:    #{requests} (#{successes} succeeded, #{requests - successes} failed)
    Wall time:   #{Float.round(wall_us / 1_000_000, 3)}s
    Throughput:  #{throughput} req/s
    Latency p50: #{us_to_ms(p50)}ms
    Latency p95: #{us_to_ms(p95)}ms
    Latency p99: #{us_to_ms(p99)}ms  (SLO: < #{@p99_threshold_ms}ms)
    """)

    if us_to_ms(p99) > @p99_threshold_ms do
      Mix.raise("reservation p99 (#{us_to_ms(p99)}ms) exceeds the #{@p99_threshold_ms}ms SLO")
    else
      Mix.shell().info("PASS: reservation p99 within SLO.")
    end
  end

  defp percentile([], _), do: 0

  defp percentile(sorted, pct) do
    index = min(length(sorted) - 1, ceil(length(sorted) * pct / 100) - 1) |> max(0)
    Enum.at(sorted, index)
  end

  defp us_to_ms(us), do: Float.round(us / 1_000, 2)

  defp setup_user! do
    n = System.unique_integer([:positive])

    case Dunda.Accounts.register_user(%{
           "email" => "load-test-#{n}@dunda.invalid",
           "password" => "password123!",
           "name" => "Load Test"
         }) do
      {:ok, user} -> user
      {:error, _} -> Dunda.Accounts.get_user_by_email("load-test-#{n}@dunda.invalid")
    end
  end

  # Dunda.Events.create_event/1 provisions the untiered InventoryPool itself
  # (fixed alongside this task — see
  # docs/phase_12_verification_observability_rollout.md finding F0), so this
  # drives the exact same path a real event creation would, rather than a
  # parallel hand-rolled setup.
  defp setup_event!(capacity_headroom) do
    n = System.unique_integer([:positive])
    capacity = capacity_headroom * 10

    {:ok, event} =
      Events.create_event(%{
        name: "Load Test Event #{n}",
        venue: "Load Test Venue",
        starts_at: DateTime.utc_now() |> DateTime.add(30, :day) |> DateTime.truncate(:second),
        price_cents: 100_000,
        capacity: capacity,
        status: "published",
        city: "Nairobi",
        currency: "KES"
      })

    event
  end
end
