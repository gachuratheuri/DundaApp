# Phase 9 — infrastructure, Redis, Kubernetes, and resilience controls

This document is the operational contract for Phase 9. PostgreSQL is the
authoritative store for reservations, payments, tickets, ledger entries, and
payout state. Redis is a disposable projection/cache and must be reconstructible
from PostgreSQL. Kubernetes manifests are deliberately fail-closed: an image
digest, secret references, policy labels, and a metrics adapter are release
inputs, not defaults.

## Release controls

1. CI resolves the image tag to a signed immutable digest and replaces
   `REPLACE_WITH_SIGNED_DIGEST` in `infra/k8s/deployment.yaml`.
2. The target cluster is checked for the labels referenced by
   `infra/k8s/networkpolicy.yaml` (`app=postgres`, `app=redis`, DNS, and the
   ingress controller). A policy simulator or an isolated canary must prove
   DNS, database, Redis, provider HTTPS, and BEAM distribution connectivity.
3. `REDIS_TLS=true` requires `REDIS_CA_CERTFILE`; credentials are delivered by
   the secret manager, never by a committed ConfigMap or image layer.
4. The external metrics adapter must expose `oban_queue_depth` with the
   `app=dunda-api` label before queue-driven HPA scaling is enabled.
5. The release evidence bundle records manifest validation, image signature,
   backup age, replica lag, and the result of the latest restore drill.

## Failure and recovery objectives

The service owner must set numeric objectives before production approval. The
minimum policy is RPO 0 for committed financial/ticket facts (synchronous
PostgreSQL durability or a documented equivalent) and an RTO no greater than
the approved event-operation window. Redis has no independent RPO/RTO: it is
recreated from PostgreSQL and may be empty after a failover.

## Graceful termination and BEAM clustering

Readiness checks return `503` when `/tmp/dunda-draining` exists. Kubernetes runs
the pre-stop hook for 20 seconds, then sends `SIGTERM`; the Oban child has a
30-second supervisor shutdown budget, within the 60-second pod grace period.
Oban leases are therefore allowed to expire or hand off rather than being
silently abandoned. The fixed distribution range (`9100`) and EPMD (`4369`)
are both declared in the Service and NetworkPolicy. Erlang cookies are read
from the secret manager. If the cluster strategy cannot resolve the headless
service, the pod must remain unready and no cross-node work may be assumed.

## Backup and restore procedure

- PostgreSQL uses encrypted managed snapshots plus continuous WAL/PITR to a
  separate account/region. Backup jobs emit age, size, checksum, and retention
  metrics; alerts fire before the maximum tolerated backup age.
- A restore is always performed into an isolated PostgreSQL instance. Apply
  migrations, run invariant/reconciliation queries, and compare row counts and
  ledger balances before considering it usable. Never restore over the live
  primary as a test.
- Redis is rebuilt only after PostgreSQL is healthy by running
  `mix dunda.phase_9_recovery --rebuild-redis` (the task delegates to
  `Dunda.Checkout.reconcile_redis_projection/0`). Reconciliation is idempotent
  and reports every mismatch; Redis is not used to decide whether money or
  inventory exists.
- Restore evidence is retained with the incident/release record. Restoration
  is exercised at least quarterly and after every schema or backup-policy
  change.

## Resilience drills

The on-call runbook must execute and record these drills against a canary:

| Fault | Expected result | Recovery evidence |
|---|---|---|
| Pod termination during an Oban job | job is retried or reaches an explicit terminal state; no duplicate settlement | job history and payment reconciliation |
| Node drain | PDB preserves capacity; replacement passes startup/readiness probes | rollout and queue-latency graphs |
| PostgreSQL failover | writes stop or fail explicitly; no Redis-only business decisions | RPO/RTO and reconciliation report |
| Redis loss | API recovers after projection rebuild; tickets/payments remain intact | rebuild output and mismatch count |
| Provider timeout/duplicate callback | durable intent remains pending and later reconciles once | provider-event audit and ledger balance |

No production release is permitted while a drill has an unknown outcome or an
unreconciled financial difference.
