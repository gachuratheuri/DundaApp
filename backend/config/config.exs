import Config

config :dunda, ecto_repos: [Dunda.Repo, Dunda.ReadRepo]

# Emergency containment is intentionally enabled by default. Phase 4 adds a
# second persisted approval gate, so changing this flag alone cannot activate
# payment, payout, resale, weak-authentication, or scraping paths.
config :dunda, :containment_mode, true
config :dunda, :portal_admin_emails, []
config :dunda, :portal_admin_user_ids, []
config :dunda, :environment, "non-production"
config :dunda, :google_client_id, nil
config :dunda, :scraper_allowed_hosts, []
config :dunda, :scraper_require_allowlist, false
config :dunda, :redis, host: "localhost", port: 6379
config :dunda, :redis_role, :projection
config :dunda, :inventory_authority, :postgres
config :dunda, :webhook_secrets, daraja: nil, pesapal: nil
config :dunda, :metrics_token, nil
config :dunda, :secure_cookies, true
config :dunda, :phase4_gate_enforced, true
config :dunda, :phase5_slo,
  error_rate_max: 0.01,
  average_latency_us_max: 500_000
config :dunda, :step_up_secret, "dev-only-step-up-secret"
config :dunda, :quote_signing_secret, "dev-only-quote-secret"
config :dunda, :checkout_provider, :pesapal
config :dunda, :max_replica_lag_seconds, 30
config :dunda, :scraper_require_allowlist, true
config :dunda, :scraper_allowed_hosts, ["ticketsasa.com", "hustlesasa.com", "mookh.com", "kenyabuzz.com"]
config :dunda, :scanner_manifest_private_key, "nWGxne/9WmC6hEr0kuwsxERJxWl7MmkZcDusAxyuf2A="
config :dunda, :scanner_manifest_public_key, "11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo="
config :dunda, :scanner_manifest_key_id, "manifest-v1"

config :dunda, Oban,
  repo: Dunda.Repo,
  plugins: [
    # Workers fail closed under Phase 0; these schedules provide the durable
    # reconciliation cadence required once the release gate is approved.
    {Oban.Plugins.Cron, crontab: [
      {"*/1 * * * *", Dunda.Workers.OutboxDispatcherWorker},
      {"*/1 * * * *", Dunda.Workers.ReservationExpiryWorker},
      {"*/5 * * * *", Dunda.Workers.InventoryReconciliationWorker},
      {"*/5 * * * *", Dunda.Workers.PaymentReconciliationWorker},
      {"0 * * * *", Dunda.Workers.FinancialReconciliationWorker},
      # DSR deadlines run regardless of Phase 0 containment — see the
      # worker moduledoc. Hourly is well inside the 5-day due-soon window.
      {"0 * * * *", Dunda.Workers.DsrDeadlineWorker}
    ]}
  ],
  queues: [
    escrow_cleanup: 10,
    scrape_dispatch: 1,
    scrape_fetch: 4,
    scrape_ingest: 10,
    payments: 3,
    inventory: 2,
    compliance: 1
  ]

# JSON library used by Ecto/Phoenix-style serialisation.
config :dunda, :json_library, Jason
config :phoenix, :json_library, Jason

# ── OpenTelemetry (Phase 12 observability) ────────────────────────────────────
# No-op exporter by default (dev/test, and prod unless an OTLP endpoint is
# configured) — config/runtime.exs enables the real OTLP exporter only when
# OTEL_EXPORTER_OTLP_ENDPOINT is set in the deploy environment, so this never
# attempts network I/O in this sandbox or in CI.
config :opentelemetry, traces_exporter: :none

# HTTP API endpoint (JSON for the mobile app + a small HTML/LiveView organiser portal).
config :dunda, DundaWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  pubsub_server: Dunda.PubSub,
  render_errors: [formats: [json: DundaWeb.ErrorJSON], layout: false],
  live_view: [signing_salt: "dunda_lv_salt_override_in_prod"]

# Default Daraja adapter; overridden per-environment below.
config :dunda, :daraja, adapter: Dunda.Payments.Daraja.HTTP

# Default Pesapal adapter (consumer hosted-checkout); overridden per-environment below.
config :dunda, :pesapal, adapter: Dunda.Billing.Pesapal.HTTP

# ── Organiser-portal asset pipeline (Tailwind + esbuild) ──────────────────────
# Replaces the dev-only Tailwind CDN with a compiled, production-ready bundle.
config :esbuild,
  version: "0.21.5",
  dunda: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

config :tailwind,
  version: "3.4.6",
  dunda: [
    args: ~w(--config=tailwind.config.js --input=css/app.css --output=../priv/static/assets/app.css),
    cd: Path.expand("../assets", __DIR__)
  ]

import_config "#{config_env()}.exs"
