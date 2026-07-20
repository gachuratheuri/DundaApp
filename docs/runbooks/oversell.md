# Runbook: checkout error-rate spike / suspected oversell

Alert: `DundaCheckoutErrorRateSpike` (`infra/observability/alerts/business_invariants.yml`)

## Symptom

5xx rate on `POST /api/checkout` exceeds 5% for 5+ minutes. This is a proxy
alert: it fires on any sustained checkout failure, including (but not proving)
an oversell attempt correctly rejected by the `inventory_pool_counts_valid`
database constraint (`backend/priv/repo/migrations/20260725000001_phase3_5_checkout_authority.exs`).

## First checks

1. `mix dunda.phase_9_recovery --report` — compare Postgres-authoritative
   inventory (`sold + reserved` per pool) against capacity. A genuine
   oversell is architecturally prevented by the guarded `Repo.update_all` in
   `Dunda.Checkout.reserve_from_quote!/4` plus the DB CHECK constraint — if
   this report shows a violation, stop and escalate immediately (Critical:
   an invariant the whole system's design depends on has failed).
2. Check application logs (redacted per `docs/log_retention_policy.md`) for
   the actual error reason returned to clients — `:inventory_unavailable`
   (expected under real contention, not a bug) vs. an unexpected exception.
3. Check `dunda_requests_total{route="/api/checkout"}` request volume — is
   this an onsale-moment traffic spike (expected, tune capacity/HPA) or a
   volume-independent failure (a real regression)?
4. Confirm `dunda_gauge{name="reconciliation_diff_count"}` is still 0 — an
   oversell would eventually surface there too if it ever slipped past the
   DB constraint (it should not be able to).

## Mitigation

- If it's genuine demand exceeding capacity: this is `:inventory_unavailable`
  behaving correctly (sold out) — no action beyond confirming the response
  the client receives is the honest "sold out" state, not a generic 500.
- If it's a real regression (exception, not a clean error tuple): check
  recent deploys against `docs/phase_12_verification_observability_rollout.md`
  § Controlled rollout — was a new checkout/fulfilment code path just
  canary-released? Consider reducing the canary percent via
  `Dunda.ReleaseApprovals.revoke/2` rather than a destructive rollback
  migration (forward-fix-only policy).

## Escalation

Financial/inventory-integrity incidents (any confirmed oversell) page
security + finance + operations release-approval roles immediately per
`Dunda.ReleaseApproval` — this is a Critical, all-hands class of incident.
