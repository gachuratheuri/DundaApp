defmodule Dunda.Application do
  use Application

  @impl true
  def start(_type, _args) do
    # Installed before any child starts so every subsequent log line —
    # including boot-time logs from the children below — passes through the
    # redaction filter (Phase 11 log-redaction hardening).
    :ok = Dunda.Logging.Redactor.install()

    # OpenTelemetry auto-instrumentation (Phase 12 observability). No-op
    # exporter unless OTEL_EXPORTER_OTLP_ENDPOINT is set (config/runtime.exs,
    # prod only) — safe to call unconditionally in every environment.
    OpentelemetryPhoenix.setup(adapter: :bandit)
    OpentelemetryEcto.setup([:dunda, :repo])
    OpentelemetryEcto.setup([:dunda, :read_repo])

    topologies = [
      k8s: [
        strategy: Cluster.Strategy.Kubernetes.DNS,
        config: [
          service: "dunda-api-headless",
          application_name: "dunda"
        ]
      ]
    ]

    # Start order is load-bearing:
    #  1. Vault     — keys available before any Ecto schema initialises
    #  2-3. Repos   — write path, then read replica
    #  4. Redix     — Redis pool before any inventory process
    #  5. Cluster   — establish distributed PubSub node discovery
    #  6. Endpoint  — accept HTTP only after all data deps are healthy
    #  7. Oban      — durable checkout/payment workers last
    children =
      [
        Dunda.Vault,
        Dunda.Repo,
        Dunda.ReadRepo,
        Dunda.Observability,
        {Redix, Application.get_env(:dunda, :redis, []) |> Keyword.put(:name, :redix)},
        {Cluster.Supervisor, [topologies, [name: Dunda.ClusterSupervisor]]}
      ] ++
        [
          # Scraper Bloom pre-filter — must exist before Oban runs ingest jobs.
          Dunda.Scraper.Dedup,
          {Phoenix.PubSub, name: Dunda.PubSub},
          DundaWeb.Endpoint,
          Supervisor.child_spec({Oban, Application.fetch_env!(:dunda, Oban)}, shutdown: 30_000)
        ]

    opts = [strategy: :one_for_one, name: Dunda.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    DundaWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
