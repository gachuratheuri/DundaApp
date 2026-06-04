import Config

if config_env() == :prod do
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
