import Config

config :dunda, ecto_repos: [Dunda.Repo, Dunda.ReadRepo]

config :dunda, Oban,
  repo: Dunda.Repo,
  plugins: [
    Oban.Plugins.Pruner,
    # Unified cron: scraper fan-out every 30 min, organiser payouts daily 06:00 EAT (03:00 UTC).
    {Oban.Plugins.Cron,
     crontab: [
       {"*/30 * * * *", Dunda.Workers.DispatchWorker},
       {"0 3 * * *", Dunda.Workers.PayoutWorker, args: %{"cron" => true}}
     ]}
  ],
  queues: [
    escrow_cleanup: 10,
    scrape_dispatch: 1,
    scrape_fetch: 4,
    scrape_ingest: 10,
    payments: 3
  ]

# JSON library used by Ecto/Phoenix-style serialisation.
config :dunda, :json_library, Jason
config :phoenix, :json_library, Jason

# HTTP API endpoint (JSON for the mobile app + a small HTML/LiveView organiser portal).
config :dunda, DundaWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [formats: [json: DundaWeb.ErrorJSON], layout: false],
  live_view: [signing_salt: "dunda_lv_salt_override_in_prod"]

# Default Daraja adapter; overridden per-environment below.
config :dunda, :daraja, adapter: Dunda.Payments.Daraja.HTTP

# Default Pesapal adapter (consumer hosted-checkout); overridden per-environment below.
config :dunda, :pesapal, adapter: Dunda.Billing.Pesapal.HTTP

import_config "#{config_env()}.exs"
