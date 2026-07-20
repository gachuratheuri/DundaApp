# Dunda

A distributed, high-concurrency ticketing platform for the Kenyan live-events
market. Engineered for the brutal traffic spikes of an onsale moment, offline
ticket validation at the venue gate, and M-Pesa-first payments.

## Repository layout

| Path | What it is |
|---|---|
| `backend/` | Elixir/OTP core — inventory isolation, M-Pesa settlement, PII encryption |
| `frontend/` | Expo / React Native attendee app ("Prismatic Brutalism" UI) |
| `infra/` | Kubernetes manifests (`k8s/`) and Redis configuration (`redis/`) |
| `dunda_full_technical_audit.md` | Senior engineering audit + implementation guide |
| `*.png`, `*.jpg` | Architecture diagrams and design references |

## Architecture at a glance

```
            ┌─────────────┐      STK push / poll      ┌──────────────┐
  Attendee  │  Expo App   │ ───────────────────────▶  │  Safaricom   │
   phone ──▶│ (frontend)  │                           │  Daraja 3.0  │
            └──────┬──────┘                           └──────────────┘
                   │ HTTPS                                   ▲
                   ▼                                         │ callback
            ┌─────────────────────────────────────────────────────┐
            │            Elixir / OTP cluster (backend)            │
            │  Horde-registered InventoryPoolServer per tier       │
            │  MpesaStateMachine  ·  Oban EscrowReclaimer          │
            └───────┬───────────────────────┬─────────────────────┘
                    │ atomic Lua            │ Ecto
                    ▼                       ▼
              ┌──────────┐           ┌──────────────┐
              │  Redis   │           │  PostgreSQL  │
              │ (escrow) │           │ primary+rep. │
              └──────────┘           └──────────────┘
```

## Core guarantees

- **No oversell** — a single atomic Redis Lua script performs check + decrement
  + escrow; inventory is further isolated to one GenServer per tier via a
  CRDT-backed `Horde.Registry`.
- **No payment is lost** — the M-Pesa state machine treats the Daraja callback
  as a fast path and a dead-letter poll as the authoritative fallback;
  settlement is idempotent on the receipt number.
- **No escrow leak** — keyspace notifications reclaim expired escrow on the fast
  path; an Oban job (`EscrowReclaimer`) is the authoritative sweep.
- **PII protected** — AES-256-GCM column encryption plus an HMAC blind index for
  lookups (Kenya ODPC alignment).

## Quick start

Backend:

```bash
cd backend && mix setup && iex -S mix
```

Frontend:

```bash
cd frontend && npm install && npx expo start
```

See `backend/README.md` and `frontend/README.md` for full details, and
`dunda_full_technical_audit.md` for the engineering rationale.

## API surface

The backend exposes a JSON API (Phoenix + Bandit):

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/healthz` | Liveness/readiness (Postgres + Redis) |
| `GET` | `/api/events` | Published upcoming catalogue with stable cursor pagination and per-tier live remaining inventory |
| `POST` | `/api/checkout` | Reserve a tier (optional `tier_id`; defaults to cheapest on-sale) + M-Pesa STK push. Buyer is always the authenticated user. |
| `GET` | `/api/tickets` | Ticket metadata and protocol-v2 credential state for the QR vault |
| `POST` | `/api/mpesa/callback` | Daraja STK result webhook |

The organiser portal at `/portal` is session-authenticated (email/password via
`/portal/login`); all LiveViews are guarded by an `on_mount` hook plus a plug.

The app consumes these through `frontend/src/api/client.ts` (`useEvents`,
`useTickets`, `checkout`) with graceful fallback to bundled sample data.

## Status

The repository is a reference implementation under emergency containment.
Payment, callback, payout, resale, weak-authentication, and scraping paths are
disabled by default. Phase 4 adds a persisted three-party release gate; an
operator must request containment exit and provide current security, finance,
and operations evidence for each feature before any globally guarded path can
activate. See `docs/phase_4_controlled_release.md` for the runbook.
Phase 5 adds read-only post-release SLO evidence and converged Kubernetes
deployment controls; it does not replace independent cluster telemetry,
backup/restore drills, or incident command.
Phase 6 adds durable resale-transfer, refund, and payout-batch accounting with
monotonic state machines; these money-moving paths remain disabled until the
independent release gate and reconciliation evidence are approved. See
`docs/phase_6_settlement_resale_payouts.md`.
The Phase 3–5 checkout authority is additive: quotes, payment intents,
PostgreSQL reservations, outbox dispatch, balanced journals, and provider-event
reconciliation are implemented but remain containment-blocked until G3–G5
evidence is complete. See `docs/phase_3_5_checkout_authority.md`.
Phase 7 replaces the unsafe shared-TOTP admission claim with versioned,
device-bound Ed25519 proofs and a venue-local coordinator model. Credential and
scanner routes remain containment-blocked until cross-language, replay,
transfer, revocation, clock-drift, and partition evidence passes. See
`docs/phase_7_ticket_security.md`.
