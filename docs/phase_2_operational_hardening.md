# Phase 2 operational hardening

Phase 2 adds the controls required to operate the Phase 1 integrity model as a
measurable, bounded, auditable service. It does not lift Phase 0 containment;
production enablement remains a separately approved release decision.

## Implemented controls

- API request body size is bounded to 1 MiB.
- Redis fixed-window rate limiting uses an atomic Lua increment/expiry script.
  Public discovery, authenticated API, authentication, and provider callbacks
  have distinct budgets. Sensitive limiters fail closed when Redis is
  unavailable; forwarded client-IP headers are not trusted.
- Browser security policy is explicit: CSP, frame/content-type protections,
  referrer policy, permissions policy, and production HSTS support.
- `/livez` is dependency-free; `/readyz` and `/healthz` use bounded primary
  database and Redis probes. Readiness is the only signal suitable for traffic
  rotation.
- Request metrics are captured without query strings, bodies, or unbounded raw
  paths. `/internal/metrics` requires a constant-time shared token and is not a
  public API.
- Append-only audit events persist critical authentication, billing, and payout
  transitions. Metadata is redacted and size-bounded; a PostgreSQL trigger
  rejects updates and deletes.
- Organiser dashboard and payout views no longer display fabricated financial or
  operational values.
- The mobile checkout client propagates an `Idempotency-Key`, so transport
  retries do not create a second reservation or payment attempt.

## Migration and verification

After an immutable database snapshot:

```text
mix ecto.migrate
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix dialyzer
mix test --cover
mix hex.audit
```

Required tests include rate-limit boundary and Redis-failure behaviour,
security-header assertions, liveness/readiness dependency failures, metrics
token rejection, audit metadata redaction/immutability, and replay tests for
authentication, billing, webhooks, payouts, and fulfilment.

## Release evidence

1. Configure `METRICS_TOKEN` in the secret manager and restrict metrics access
   at the ingress/network-policy layer.
2. Set production proxy trust only through a separately reviewed ingress plug;
   do not reinterpret `X-Forwarded-For` inside the rate limiter.
3. Verify alert thresholds for readiness failures, 5xx rate, rate-limit spikes,
   Oban failures, payout rows awaiting reconciliation, and audit-write errors.
4. Test PostgreSQL and Redis restore procedures against immutable snapshots and
   record recovery-point and recovery-time measurements.
5. Obtain independent approval before changing `containment_mode` or exposing
   any previously disabled payment/callback route.
