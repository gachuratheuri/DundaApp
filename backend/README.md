# Dunda — Backend (Elixir/OTP)

Distributed ticketing core for the Dunda live-events platform. Handles inventory
isolation, M-Pesa settlement, and PII encryption.

## Architecture

| Concern | Mechanism |
|---|---|
| Inventory authority | PostgreSQL `inventory_pools` and `inventory_reservations`; guarded updates and row locks preserve capacity |
| Redis role | Rebuildable remaining-count projection, rate limiting, and ephemeral coordination only |
| Reservation expiry | Locked payment/reservation transition; uncertain provider outcomes are retained for reconciliation |
| Payments | Unified quote/payment-intent state machine with provider adapters, durable events, and an outbox |
| Daraja client | Behaviour (`Dunda.Payments.Daraja`) with `HTTP` (prod) and `Sandbox` (dev/test) adapters |
| PII at rest | `cloak_ecto` AES-256-GCM + HMAC-SHA256 blind index for lookups |
| Clustering | `libcluster` Kubernetes DNS strategy |

Scraper HTML targets are HTTPS-only and production requires the
`SCRAPER_ALLOWED_HOSTS` allow-list. Redirects, private/link-local/metadata
addresses, oversized responses, and structurally invalid provider envelopes
are rejected. Scraped provenance and run freshness are persisted in
`events` and `scrape_source_runs`.

## Prerequisites

- Elixir `~> 1.15` / OTP 26+
- PostgreSQL 14+
- Redis 7+ (see `../infra/redis/redis.conf`)

## HTTP API (Phoenix + Bandit)

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/healthz` | Liveness/readiness (checks Postgres + Redis); 503 when degraded |
| `GET` | `/livez` | Process liveness only; no dependency calls |
| `GET` | `/readyz` | Bounded Postgres + Redis + replica-lag readiness check |
| `GET` | `/internal/release-health` | Token-protected post-release SLO evidence |
| `GET` | `/api/privacy/export` | Authenticated minimised data export |
| `POST` | `/api/privacy/requests` | Authenticated data-subject request creation |
| `GET` | `/api/events` | Published upcoming catalogue; supports bounded `limit`, opaque `after` cursor, `category`, and `city` filters |
| `GET` | `/api/events/:id` | Single event |
| `POST` | `/api/resale/listings/:id/intent` | Create an idempotent resale payment intent; transfer occurs only after authoritative completion |
| `POST` | `/api/quotes` | Create a short-lived server-priced quote (containment-blocked until G3) |
| `POST` | `/api/checkout` | Create an idempotent quote-bound payment intent (containment-blocked until G3) |
| `GET` | `/api/checkout/:id/status` | Read a payment intent only for its owning user |
| `GET` | `/api/tickets` | Active entitlements (server-signed protocol-v2 credential metadata; no shared secret) |
| `POST` | `/api/tickets/:id/device-challenge` | Issue a short-lived device-binding challenge |
| `POST` | `/api/tickets/:id/bind-device` | Bind an attendee Ed25519 public key to a ticket |
| `POST` | `/api/scanner/admissions` | Coordinator-serialised protocol-v2 admission |
| `GET` | `/api/scanner/manifests/:event_id` | Signed event manifest for venue edge devices |
| `POST` | `/api/mpesa/callback` | Safaricom Daraja STK result webhook |

`POST /api/checkout` body:

```json
{ "quote_id": "2fb...", "phone": "0712345678" }
```

Checkout requests must include a unique `Idempotency-Key` header (16–200
bytes). Retries with the same key and parameters return the original
transaction; changing parameters with a reused key is rejected.

## Getting started

```bash
mix setup                       # deps.get + ecto.create + ecto.migrate
mix run priv/repo/seeds.exs     # seed events + Redis inventory
iex -S mix                      # boots the API on http://localhost:4000
```

Dev uses the offline `Daraja.Sandbox` adapter and dev-only encryption keys
(`config/dev.exs`), so no Safaricom credentials are required locally.

## Tests

```bash
mix test
```

Tests run against the SQL sandbox and the in-memory Daraja adapter — no network.

## Production configuration

`config/runtime.exs` reads these environment variables (fail-fast if missing):

| Variable | Purpose |
|---|---|
| `DATABASE_PRIMARY_URL` / `DATABASE_REPLICA_URL` | Postgres primary / read replica |
| `ENCRYPTION_KEY` | base64 AES-256 key for PII |
| `BLIND_INDEX_KEY` | base64 HMAC key (MUST differ from `ENCRYPTION_KEY`) |
| `REDIS_HOST` | Redis host |
| `DARAJA_CONSUMER_KEY` / `DARAJA_CONSUMER_SECRET` | Daraja OAuth |
| `DARAJA_SHORTCODE` / `DARAJA_PASSKEY` | Lipa na M-Pesa |
| `DARAJA_CALLBACK_URL` | STK push callback endpoint |
| `METRICS_TOKEN` | Shared token for the restricted `/internal/metrics` endpoint |
| `STEP_UP_SECRET` | Secret for short-lived payout-destination step-up capabilities |
| `QUOTE_SIGNING_SECRET` | Secret used to bind short-lived server-priced quotes to their purchaser and terms |
| `SCANNER_MANIFEST_PRIVATE_KEY` / `SCANNER_MANIFEST_PUBLIC_KEY` | Managed Ed25519 key pair used to sign and verify venue event manifests |
| `SCANNER_MANIFEST_KEY_ID` | Rotation identifier for the active scanner-manifest verification key |
| `DUNDA_CONTAINMENT_MODE` | Explicit release request (`false`); Phase 4 approvals remain mandatory |

Phase 3 privacy and retention operations are documented in
`../docs/phase_3_compliance_continuity.md`. The retention task is dry-run by
default and cannot execute while Phase 0 containment is active.

Phase 4 release approvals are reported read-only by
`mix dunda.phase_4_release`; persisted security, finance, and operations
approvals are required before any globally guarded feature can activate.
Phase 5 post-release SLO and governance evidence is reported read-only by
`mix dunda.phase_5_readiness` and `GET /internal/release-health`.
Phase 6 settlement, resale, refund, and payout controls are documented in
`../docs/phase_6_settlement_resale_payouts.md` and remain behind the release
gate.
Phases 3–5 unified checkout, PostgreSQL inventory authority, settlement,
fulfilment, outbox, and journal controls are documented in
`../docs/phase_3_5_checkout_authority.md`; their routes remain containment-
blocked until the corresponding evidence gates pass.

Generate keys with:

```bash
mix run -e 'IO.puts(Base.encode64(:crypto.strong_rand_bytes(32)))'
```

## Quality gates

```bash
mix format --check-formatted
mix credo --strict
mix dialyzer
```
