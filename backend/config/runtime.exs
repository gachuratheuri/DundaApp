import Config

if config_env() == :prod do
  # Phase 0 is fail-closed in release builds. The operator may request the
  # containment flag to be lifted only after the reviewed exit criteria pass;
  # the independent persisted Phase 4 approval gate still denies every guarded
  # feature when approvals are absent, expired, revoked, or inconsistent.
  release_requested =
    System.get_env("DUNDA_CONTAINMENT_MODE", "true")
    |> String.trim()
    |> String.downcase()
    |> then(&(&1 in ~w(false 0 no)))

  config :dunda, :containment_mode, not release_requested
  config :dunda, :phase4_gate_enforced, true
  config :dunda, :step_up_secret, System.fetch_env!("STEP_UP_SECRET")
  config :dunda, :quote_signing_secret, System.fetch_env!("QUOTE_SIGNING_SECRET")
  config :dunda, :checkout_provider, System.get_env("CHECKOUT_PROVIDER", "pesapal") |> String.to_atom()
  config :dunda, :max_replica_lag_seconds, String.to_integer(System.get_env("MAX_REPLICA_LAG_SECONDS", "30"))
  config :dunda, :scraper_require_allowlist, System.get_env("SCRAPER_REQUIRE_ALLOWLIST", "true") == "true"
  config :dunda, :scraper_allowed_hosts, System.get_env("SCRAPER_ALLOWED_HOSTS", "") |> String.split(",", trim: true)
  config :dunda, :scanner_manifest_private_key, System.fetch_env!("SCANNER_MANIFEST_PRIVATE_KEY")
  config :dunda, :scanner_manifest_public_key, System.fetch_env!("SCANNER_MANIFEST_PUBLIC_KEY")
  config :dunda, :scanner_manifest_key_id, System.get_env("SCANNER_MANIFEST_KEY_ID", "manifest-v1")
  config :dunda, :environment, "non-production"
  config :dunda, :google_client_id, System.get_env("GOOGLE_CLIENT_ID")
  config :dunda, :otp_secret, System.fetch_env!("OTP_HMAC_SECRET")
  config :dunda, :metrics_token, System.fetch_env!("METRICS_TOKEN")
  config :dunda, :webhook_secrets,
    daraja: System.fetch_env!("DARAJA_CALLBACK_SECRET"),
    pesapal: System.fetch_env!("PESAPAL_IPN_SECRET")
  redis_opts = [
    host: System.get_env("REDIS_HOST", "localhost"),
    port: String.to_integer(System.get_env("REDIS_PORT", "6379")),
    password: System.fetch_env!("REDIS_PASSWORD")
  ]

  redis_opts =
    if System.get_env("REDIS_TLS", "true") == "true" do
      Keyword.merge(redis_opts,
        transport: :ssl,
        socket_opts: [verify: :verify_peer, cacertfile: System.fetch_env!("REDIS_CA_CERTFILE")]
      )
    else
      redis_opts
    end

  config :dunda, :redis, redis_opts
  config :dunda, :redis_role, :projection
  config :kernel, inet_dist_listen_min: 9100, inet_dist_listen_max: 9100
  config :dunda, :inventory_authority,
    case System.get_env("INVENTORY_AUTHORITY", "postgres") do
      "postgres" -> :postgres
      "redis_legacy" -> :redis_legacy
      other -> raise "unsupported INVENTORY_AUTHORITY=#{other}; use postgres or explicitly gated redis_legacy"
    end

  config :dunda, DundaWeb.Endpoint,
    server: true,
    http: [ip: {0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT", "4000"))],
    url: [host: System.fetch_env!("PHX_HOST"), port: 443, scheme: "https"],
    secret_key_base: System.fetch_env!("SECRET_KEY_BASE"),
    entitlement_signing_key: System.fetch_env!("ENTITLEMENT_SIGNING_KEY"),
    live_view: [signing_salt: System.fetch_env!("LIVE_VIEW_SIGNING_SALT")]

  config :dunda, Dunda.Repo,
    url: System.fetch_env!("DATABASE_PRIMARY_URL"),
    pool_size: 20

  config :dunda, Dunda.ReadRepo,
    url: System.fetch_env!("DATABASE_REPLICA_URL"),
    pool_size: 40,
    after_connect: {Postgrex, :query!, ["SET default_transaction_read_only = on", []]}

  config :dunda, Dunda.Vault,
    ciphers: [
      default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1",
                key: Base.decode64!(System.fetch_env!("ENCRYPTION_KEY")),
                iv_length: 12}
    ]

  # Deterministic blind-index key — MUST be distinct from ENCRYPTION_KEY.
  config :dunda, Dunda.Hashed.HMAC,
    algorithm: :sha256,
    secret: Base.decode64!(System.fetch_env!("BLIND_INDEX_KEY"))

  # Safaricom Daraja 3.0 production credentials (consumer STK push + B2C payouts).
  config :dunda, :daraja,
    adapter: Dunda.Payments.Daraja.HTTP,
    base_url: System.get_env("DARAJA_BASE_URL", "https://api.safaricom.co.ke"),
    consumer_key: System.fetch_env!("DARAJA_CONSUMER_KEY"),
    consumer_secret: System.fetch_env!("DARAJA_CONSUMER_SECRET"),
    shortcode: System.fetch_env!("DARAJA_SHORTCODE"),
    passkey: System.fetch_env!("DARAJA_PASSKEY"),
    callback_url: System.fetch_env!("DARAJA_CALLBACK_URL"),
    # B2C (organiser payout) credentials.
    b2c_shortcode: System.get_env("DARAJA_B2C_SHORTCODE"),
    b2c_initiator: System.get_env("DARAJA_B2C_INITIATOR"),
    b2c_security_credential: System.get_env("DARAJA_B2C_SECURITY_CREDENTIAL"),
    b2c_result_url: System.get_env("DARAJA_B2C_RESULT_URL")

  # Pesapal API 3.0 production credentials (consumer hosted checkout + IPN).
  # PESAPAL_IPN_ID is Priority 1 in Dunda.Billing.Setup's four-level resolution.
  config :dunda, :pesapal,
    adapter: Dunda.Billing.Pesapal.HTTP,
    base_url: System.get_env("PESAPAL_BASE_URL", "https://pay.pesapal.com/v3"),
    consumer_key: System.fetch_env!("PESAPAL_CONSUMER_KEY"),
    consumer_secret: System.fetch_env!("PESAPAL_CONSUMER_SECRET"),
    ipn_url: System.fetch_env!("PESAPAL_IPN_URL"),
    ipn_id: System.get_env("PESAPAL_IPN_ID"),
    callback_url: System.fetch_env!("PESAPAL_CALLBACK_URL")
end
