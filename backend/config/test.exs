import Config

# Tests use isolated sandbox adapters; production-like environments remain in
# emergency containment. No test configuration may be reused for deployment.
config :dunda, :containment_mode, false
config :dunda, :environment, "test"
config :dunda, :otp_secret, "test-only-otp-secret"
config :dunda, :webhook_secrets, daraja: "test-daraja-webhook-secret", pesapal: "test-pesapal-webhook-secret"
config :dunda, :metrics_token, "test-metrics-token"
config :dunda, :secure_cookies, false
config :dunda, :phase4_gate_enforced, false
config :dunda, :step_up_secret, "test-step-up-secret"
config :dunda, :quote_signing_secret, "test-quote-secret"
config :dunda, :checkout_provider, :pesapal
config :dunda, :inventory_authority, :redis_legacy
config :dunda, :redis_role, :transactional_legacy
config :dunda, :scanner_manifest_private_key, "nWGxne/9WmC6hEr0kuwsxERJxWl7MmkZcDusAxyuf2A="
config :dunda, :scanner_manifest_public_key, "11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo="
config :dunda, :scanner_manifest_key_id, "manifest-test-v1"

config :dunda, Dunda.Repo,
  username: System.get_env("PGUSER", "postgres"),
  password: System.get_env("PGPASSWORD", "postgres"),
  hostname: System.get_env("PGHOST", "localhost"),
  database: "dunda_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :dunda, Dunda.ReadRepo,
  username: System.get_env("PGUSER", "postgres"),
  password: System.get_env("PGPASSWORD", "postgres"),
  hostname: System.get_env("PGHOST", "localhost"),
  database: "dunda_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

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

# Never hit the network in tests.
config :dunda, :daraja, adapter: Dunda.Payments.Daraja.Sandbox
config :dunda, :pesapal, adapter: Dunda.Billing.Pesapal.Sandbox

config :dunda, DundaWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "test_secret_key_base_at_least_64_bytes_long_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  entitlement_signing_key: "test-entitlement-signing-key",
  live_view: [signing_salt: "dunda_lv_test_salt"],
  server: false

# Disable Oban job execution during tests; jobs are asserted via Oban.Testing.
config :dunda, Oban, testing: :inline, plugins: []

config :logger, level: :warning
