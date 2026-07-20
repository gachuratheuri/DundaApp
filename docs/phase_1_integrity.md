# Phase 1 security and integrity implementation

Phase 1 establishes the invariants required before any payment or organiser
flow can be released from emergency containment. The implementation is
fail-closed in the current release; Phase 0 routes remain disabled until the
operational exit evidence below is independently reviewed.

## Implemented controls

- Google ID tokens are verified through Google's token-introspection endpoint,
  with issuer, audience, expiry, subject, and verified-email checks. Local JWT
  payload decoding and implicit OAuth/password-account linking were removed.
- OTPs are six-digit, cryptographically random, Redis-backed, hashed, expiring,
  single-use values. Delivery requires an explicit provider adapter; no fixed
  development code exists.
- Pesapal order creation is identity-bound to the authenticated user and derives
  event, organisation, tier, price, currency, and quantity from authoritative
  database state. Client-supplied amount, organisation, and user identifiers
  are ignored. An `Idempotency-Key` is persisted and unique per user.
- M-Pesa checkout requires an `Idempotency-Key`; Redis stores a 24-hour request
  fingerprint so retries return the original transaction and parameter changes
  are rejected rather than initiating a second charge.
- Ticket fulfilment has a database-backed `fulfillment_key` uniqueness invariant
  so callback/retry races cannot mint the same logical ticket twice.
- Payout submission persists a pending/processing payout and no longer marks
  orders paid merely because Daraja accepted a request. Final settlement must
  be reconciled from a provider result or an approved manual procedure.
- Organiser reads and writes are tenant-scoped through accepted organisation
  memberships; the event editor no longer uses a hard-coded organisation id.
- Redis is explicitly standalone for Phase 1 because the checkout Lua script
  touches a cross-pool user lock. Cluster sharding is deferred until a new
  multi-key locking protocol is designed and proven.
- Public event reads exclude drafts, cancelled events, and other non-published
  records.
- Organiser-controlled HTML fetches require HTTPS, DNS resolution to a public
  address, an optional production host allow-list, redirect blocking, and a
  bounded response body.
- Redis credentials are now supplied through release configuration rather than
  being implicit; the Phase 1 topology is intentionally standalone until the
  multi-key checkout protocol is redesigned for Cluster.

## Migration and verification

Run migrations only after a database snapshot and review:

```text
mix ecto.migrate
mix test
mix credo --strict
mix dialyzer
```

The new migration adds authoritative billing fields, order constraints, and
the partial unique fulfilment index. It does not delete or rewrite existing
tickets.

## Required release evidence

1. Configure and test Google audience, OTP provider, Daraja/Pesapal callback
   secrets, and all signing/encryption keys in the secret manager.
2. Execute a replay test matrix: duplicate idempotency key, duplicate IPN,
   duplicate M-Pesa callback, callback/poller race, fulfilment retry, and payout
   provider timeout. Each case must produce one financial effect and one set of
   tickets.
3. Reconcile pre-existing orders, tickets, escrows, ledger entries, payouts,
   and duplicate identities using the Phase 0 audit output.
4. Verify organisation membership fixtures and negative cross-tenant tests for
   every organiser LiveView and API endpoint.
5. Obtain independent security review and staged canary approval before
   changing containment configuration. No environment variable alone may lift
   the current release gate.
