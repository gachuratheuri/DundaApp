# Dunda — Backend (Elixir/OTP)

Distributed ticketing core for the Dunda live-events platform. Handles inventory
isolation, M-Pesa settlement, and PII encryption.

## Architecture

| Concern | Mechanism |
|---|---|
| Inventory isolation | One `InventoryPoolServer` GenServer per ticket tier, named via `Horde.Registry` (CRDT-backed, cluster-wide) |
| Oversell safety | Atomic Redis Lua script (`priv/lua/inventory_checkout.lua`) — check + decrement + escrow in one round trip |
| Escrow expiry | Redis keyspace notifications (fast path) **plus** `EscrowReclaimer` Oban job (authoritative) |
| Payments | `MpesaStateMachine` (`gen_state_machine`) with Daraja callback + dead-letter polling |
| Daraja client | Behaviour (`Dunda.Payments.Daraja`) with `HTTP` (prod) and `Sandbox` (dev/test) adapters |
| PII at rest | `cloak_ecto` AES-256-GCM + HMAC-SHA256 blind index for lookups |
| Clustering | `libcluster` Kubernetes DNS strategy |

## Prerequisites

- Elixir `~> 1.15` / OTP 26+
- PostgreSQL 14+
- Redis 7+ (see `../infra/redis/redis.conf`)

## HTTP API (Phoenix + Bandit)

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/healthz` | Liveness/readiness (checks Postgres + Redis); 503 when degraded |
| `GET` | `/api/events` | List events with live `remaining` inventory |
| `GET` | `/api/events/:id` | Single event |
| `POST` | `/api/checkout` | Reserve inventory + initiate M-Pesa STK push |
| `GET` | `/api/tickets` | Active entitlements (signed JWT + `totp_secret`) |
| `POST` | `/api/mpesa/callback` | Safaricom Daraja STK result webhook |

`POST /api/checkout` body:

```json
{ "event_id": "1", "user_id": "u_123", "phone": "0712345678", "quantity": 2 }
```

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
