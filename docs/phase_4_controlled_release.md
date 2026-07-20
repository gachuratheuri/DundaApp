# Phase 4 controlled release and canary governance

Phase 4 introduces the final code-level release gate. It does not switch on
payments, callbacks, payouts, OTP, scraping, or resale. It makes activation a
persisted, auditable, multi-party decision rather than an environment-variable
side effect.

In a production release, `DUNDA_CONTAINMENT_MODE=false` is necessary to request
activation, but it is never sufficient: the persisted Phase 4 gate remains
enforced and independently requires all three approvals for every guarded
feature.

## Implemented controls

- `release_approvals` stores feature, approval role, approver reference,
  evidence URI, expiry, revocation, metadata, and canary percentage.
- Every feature requires distinct current approvals from `security`, `finance`,
  and `operations`.
- Expired or revoked approvals fail closed.
- Global feature guards require 100% canary approval. Subject-aware canary
  decisions are available through `Dunda.Containment.permitted?/2`, but existing
  payment paths do not silently enter a canary.
- Organiser portal access and portal mutations are independently gated; lifting
  the emergency flag alone cannot expose membership data or write operations.
- Database/configuration failures deny release.
- `mix dunda.phase_4_release` reports the gate state read-only.
- Kubernetes readiness/liveness probes are separated, so rollout systems can
  remove unhealthy pods without confusing process liveness with dependency
  readiness.

## Gate operation

After migrations and independent review:

```text
mix ecto.migrate
mix dunda.phase_4_release
```

Approvals must be inserted through the controlled operator workflow for each
feature (including `portal_access` and `portal_mutations`) with:

1. independent approver identities;
2. immutable evidence URI (test report, security review, financial
   reconciliation, or incident approval);
3. explicit expiry;
4. canary percentage and rollback owner;
5. recorded provider, database, Redis, and restore-drill evidence.

No API endpoint is provided to self-approve a release. Approval provisioning is
an operator control and should be performed through a separately authenticated
change-management system or reviewed database operation.

## Required canary evidence

- replay and race matrix passes for checkout, IPN, callbacks, fulfilment, and
  payouts;
- no unexplained 5xx, rate-limit, audit-write, readiness, or reconciliation
  alerts during the observation window;
- financial ledger and provider totals reconcile exactly;
- rollback is tested by revoking one approval and verifying immediate fail-closed
  behaviour;
- independent security, finance, and operations sign-off is recorded.
