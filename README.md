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
| `GET` | `/api/events` | Discover feed with live remaining inventory |
| `POST` | `/api/checkout` | Reserve inventory + initiate M-Pesa STK push |
| `GET` | `/api/tickets` | Signed entitlement tokens for the QR vault |
| `POST` | `/api/mpesa/callback` | Daraja STK result webhook |

The app consumes these through `frontend/src/api/client.ts` (`useEvents`,
`useTickets`, `checkout`) with graceful fallback to bundled sample data.

## Status

Reference implementation with a working end-to-end path: discover → checkout →
M-Pesa (sandbox) → settlement → signed offline ticket. Next steps: attendee
auth, multi-tier ticketing, the Kotlin venue scanner, and the Bloom-filter
revocation sync described in `dunda_full_technical_audit.md`.
