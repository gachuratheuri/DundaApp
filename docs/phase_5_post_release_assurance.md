# Phase 5 post-release assurance and resilience

Phase 5 governs the period after a controlled release has been approved. It
does not grant release authority and it does not automatically revoke
approvals from a single pod's local counters. Its purpose is to produce
repeatable evidence for an operator, an external metrics system, and an
incident review.

## Implemented controls

- `Dunda.ReleaseHealth` evaluates request error rate and average latency from
  structured node counters using explicit, configurable thresholds.
- `GET /internal/release-health` exposes the read-only evaluation behind the
  same constant-time internal metrics token and rate limit as `/internal/metrics`.
- `mix dunda.phase_5_readiness` reports containment state, every Phase 4 gate,
  and the current SLO report without changing state.
- Metrics now have a structured counter API; the existing JSON snapshot remains
  backward compatible for operators and tests.
- Kubernetes deployment configuration has one canonical Deployment and uses
  separate liveness/readiness probes, graceful termination, non-root execution,
  and dropped Linux capabilities.

## SLO interpretation

The initial thresholds are an HTTP 5xx rate of at most 1% and average request
latency of at most 500 ms. These are guardrails, not a substitute for a
time-windowed, multi-replica Prometheus query. Because the in-process registry
is node-local and cumulative, the report is evidence only; an operator must
correlate it with the provider, database, Redis, audit, and reconciliation
signals before revoking or extending a Phase 4 approval.

## Required operating procedure

```text
mix ecto.migrate
mix dunda.phase_4_release
mix dunda.phase_5_readiness
```

During a canary or full release, record the report at fixed observation
intervals, compare it with cluster-wide telemetry, and retain the output with
the approval evidence URI. If an SLO, financial reconciliation, readiness, or
security invariant fails, revoke at least one relevant Phase 4 approval through
the controlled operator workflow; the application then fails closed on the
next guarded operation.

## Recovery evidence

Before production traffic is enabled, operators must retain proof of:

1. PostgreSQL backup completion and a restore drill into an isolated target;
2. Redis persistence/failover validation and inventory reconciliation against
   PostgreSQL truth;
3. duplicate callback, poller, fulfilment, and payout replay tests;
4. a tested Kubernetes rollback to the previous signed image;
5. an incident owner, escalation path, and timestamped approval/revocation
   records.

No readiness report is considered sufficient by itself to override Phase 4,
financial, privacy, or security controls.
