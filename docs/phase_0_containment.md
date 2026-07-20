# Phase 0 emergency containment runbook

Status: implemented in source; deployment and financial controls remain operational actions.

Phase 0 is a fail-closed incident response state. The repository is labelled
`non-production`, payment initiation and callbacks are disabled, resale is
disabled, organiser access requires an explicit administrator allow-list and
all organiser LiveView events are read-only, scraper and payment workers cancel
without side effects, and Oban cron/pruning are removed to preserve evidence.

## Code controls

- `POST /api/auth/google`, both OTP endpoints, billing order creation, checkout,
  M-Pesa callback, Pesapal IPN, and every resale endpoint return HTTP 503 with a
  stable `phase_0_containment` code and `Retry-After` header.
- `Dunda.Payments`, `Dunda.Billing`, `Dunda.Market`, and all payment/scraper
  workers enforce the same invariant defensively; route protection alone is not
  relied upon.
- Portal sessions are accepted only when the user id or normalised email is in
  `PORTAL_ADMIN_USER_IDS`/`PORTAL_ADMIN_EMAILS` (or the equivalent application
  configuration). Empty allow-lists fail closed.
- `mix dunda.phase_0_audit` is read-only and reports order, ticket, ledger,
  resale, and duplicate fulfilment-key counts for reconciliation.

## Required operator actions before any release

These actions cannot be completed from source code and must be recorded in the
incident system with an operator, timestamp, evidence URI, and approval:

1. Disable/rotate Daraja, Pesapal, database, Redis, signing, OAuth, and social
   API credentials. Revoke sessions and tokens issued before containment.
2. Take immutable, access-controlled PostgreSQL and Redis snapshots. Preserve
   Oban jobs, logs, callback payloads, and audit records; do not run destructive
   cleanup or pruning.
3. Run `mix dunda.phase_0_audit` against the isolated database and reconcile
   orders, ledger settlements, ticket entitlements, inventory escrows, resale
   transfers, and payout acknowledgements. Export output to incident storage.
4. Inspect active sessions, privileged accounts, webhook logs, and provider
   dashboards for unauthorised activity. Freeze or reverse disputed transfers
   through the provider’s documented process.
5. Verify deployment manifests, network policy, Redis topology, database
   backups, and secret-manager state. Record independent review sign-off.

Containment must not be lifted by changing an environment variable in an
unreviewed deployment. The Phase 4 gate now makes the production setting only
a necessary release request: persisted, current, independent approvals are
still required for every guarded feature.
