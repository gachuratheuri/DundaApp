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
            │  Checkout aggregate · durable outbox · Oban workers  │
            │  Provider adapters · explicit payment state machine  │
            └───────┬───────────────────────┬─────────────────────┘
                    │ rebuildable cache     │ authoritative transactions
                    ▼                       ▼
              ┌──────────┐           ┌──────────────┐
              │  Redis   │           │  PostgreSQL  │
              │projection│           │ primary+rep. │
              └──────────┘           └──────────────┘
```

## Enforced invariants

- **Inventory authority is PostgreSQL** — guarded updates, row locks, and CHECK
  constraints preserve `sold + reserved <= capacity`; Redis is disposable.
- **Payment effects are idempotent** — provider identifiers, settlements,
  ticket batches, and outbox keys are uniquely constrained. Uncertain provider
  outcomes remain explicit and are reconciled rather than discarded.
- **Fulfilment and accounting are transactional** — settlement, reservation
  conversion, ticket creation, balanced journal entries, state transitions,
  and notification intents commit together.
- **PII controls are field-specific** — sensitive contact and payout fields use
  authenticated encryption and blind indexes where equality lookup is needed.

These are design and database invariants, not a production-readiness claim.
Release remains prohibited until the documented integration, concurrency,
recovery, security, and reconciliation gates have produced current evidence.

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
| `POST` | `/api/quotes` | Create an expiring server-authoritative quote for the authenticated buyer. |
| `POST` | `/api/checkout` | Reserve the quoted tier and create a provider-neutral payment intent. Requires `Idempotency-Key`. |
| `GET` | `/api/checkout/:id/status` | Read an owned payment intent's durable state. |
| `GET` | `/api/tickets` | Ticket metadata and protocol-v2 credential state for the QR vault |
| `POST` | `/api/auth/refresh` | Rotate a device refresh token and issue a 15-minute access token. |
| `POST` | `/api/auth/logout` | Revoke the current device session or all account sessions. |
| `POST` | `/api/providers/:provider/events` | Durable provider-event ingress for `mpesa` and `pesapal` (containment-gated). |
| `POST` | `/api/mpesa/b2c/result` | Daraja B2C result ingress; requires the configured callback query token or a trusted edge-injected header. |

`POST /api/mpesa/callback` and the direct Pesapal IPN routes remain explicitly
disabled. Daraja cannot supply a custom application header, so production must
configure its exact B2C result URL with the high-entropy `token` query value,
or terminate provider traffic at an allow-listed edge that injects
`x-dunda-webhook-secret`. Query strings must be excluded from access logs.

The organiser portal at `/portal` is session-authenticated (email/password via
`/portal/login`); all LiveViews are guarded by an `on_mount` hook plus a plug.

The app consumes these through `frontend/src/api/client.ts` (`useEvents`,
`useTickets`, `checkout`). Ticket failures return no fabricated credential;
catalogue demo data is development-only and explicitly labelled.

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
Phase 11 completes the data-governance program: a verified data inventory and
DPIA, encryption of the remaining plaintext checkout contact fields, a real
key-rotation mechanism, log redaction, all five DSR rights with deadline
monitoring, and consent records. See `docs/phase_11_privacy_governance.md`.
Phase 12 adds the property-based/contract/fault-injection/migration/mutation/
performance test hierarchy, a real Prometheus scrape endpoint with
business-invariant metrics, dashboards, alerts, and runbooks, and extends
release governance to the full five-stakeholder set. It also documents,
rather than hides, what it found while writing that test suite: a Critical
defect (no code path provisioned inventory for a newly created event, so the
Phase 3–5 checkout authority did not function end-to-end — now fixed, see
`test/dunda/events_inventory_pool_test.exs`) and a High organiser-portal
authorization gap. Portal entry is now membership-gated and tenant-sensitive
mutations use context-level permission checks. **Exit gate G12 is not met** — see
`docs/phase_12_verification_observability_rollout.md` for the full findings
table and evidence linkage. On 24 July 2026 the backend compiled with warnings
as errors, Credo and Dialyzer passed, and the frontend passed typecheck, lint,
tests, dependency audit and a three-platform production export. The full
database suite and migration drill still require PostgreSQL/Redis and remain a
release-blocking CI gate.
