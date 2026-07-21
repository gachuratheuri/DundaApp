import Config

config :dunda, :containment_mode, true
config :dunda, :environment, "non-production"
config :dunda, :otp_secret, "dev-only-otp-secret-change-before-use"

config :dunda, :webhook_secrets,
  daraja: "dev-daraja-webhook-secret",
  pesapal: "dev-pesapal-webhook-secret"

config :dunda, :metrics_token, "dev-metrics-token"
config :dunda, :secure_cookies, false
config :dunda, :phase4_gate_enforced, false

# ── Local Postgres (primary + replica point at the same DB in dev) ────────────
config :dunda, Dunda.Repo,
  username: System.get_env("PGUSER", "postgres"),
  password: System.get_env("PGPASSWORD", "postgres"),
  hostname: System.get_env("PGHOST", "localhost"),
  database: "dunda_dev",
  pool_size: 10,
  show_sensitive_data_on_connection_error: true

config :dunda, Dunda.ReadRepo,
  username: System.get_env("PGUSER", "postgres"),
  password: System.get_env("PGPASSWORD", "postgres"),
  hostname: System.get_env("PGHOST", "localhost"),
  database: "dunda_dev",
  pool_size: 10

# ── Dev-only encryption keys (NEVER use these in production) ──────────────────
config :dunda, Dunda.Vault,
  ciphers: [
    default:
      {Cloak.Ciphers.AES.GCM,
       tag: "AES.GCM.V1",
       key: Base.decode64!("3Jnb0hZiHIzHTOih7t2cTEPEpY98Tu1wvQkPfq/XwqE="),
       iv_length: 12}
  ]

config :dunda, Dunda.Hashed.HMAC,
  algorithm: :sha256,
  secret: "dev-only-hmac-blind-index-secret-not-for-prod"

# Use the offline sandbox adapters so checkout/billing flows work without external APIs.
config :dunda, :daraja, adapter: Dunda.Payments.Daraja.Sandbox
config :dunda, :pesapal, adapter: Dunda.Billing.Pesapal.Sandbox

config :dunda, DundaWeb.Endpoint,
  server: true,
  http: [ip: {0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT", "4000"))],
  debug_errors: true,
  # Dev-only secret; runtime.exs supplies a real one in prod.
  secret_key_base: "dev_secret_key_base_at_least_64_bytes_long_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  # Entitlement-token signing key (dev only).
  entitlement_signing_key: "dev-entitlement-signing-key",
  live_view: [signing_salt: "dunda_lv_dev_salt"],
  # Live-reload not configured; the portal is a low-traffic admin surface.
  check_origin: false,
  # Rebuild portal assets on change in dev.
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:dunda, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:dunda, ~w(--watch)]}
  ]

config :logger, level: :debug
