# Runbook: reservation latency breach / stuck or duplicated payment events

Alerts: `DundaReservationLatencyBreach`, `DundaWebhookDuplicateSpike`
(`infra/observability/alerts/business_invariants.yml`)

## Symptom

Either: reservation p99 latency (from the `dunda_latency_bucket_count`
histogram on `/api/checkout`) exceeds the 150ms SLO; or a sustained rate of
duplicate webhook deliveries (`webhook_duplicate_total`, incremented in
`Dunda.Checkout.record_provider_event/1` whenever the unique
`(provider, provider_event_id)` constraint rejects a re-delivery).

## First checks

1. **Latency**: `mix dunda.load_test --requests 200 --concurrency 20` against
   a canary/staging environment reproduces the reservation path in isolation
   — compare its p99 to production's. Check Postgres primary connection pool
   saturation and lock contention on `inventory_pools` (a hot single-tier
   pool under extreme contention is a known, documented scaling limit — see
   `docs/phase_9_infrastructure_resilience.md`; the plan's own guidance is
   "benchmark, then shard the pool only after a reproducible bottleneck").
2. **Duplicates**: duplicates are expected under at-least-once provider
   delivery and are provably handled safely
   (`test/dunda/payments/duplicate_callback_test.exs`,
   `test/dunda/payments/reordered_events_test.exs`) — the alert exists to
   catch a *rate* anomaly, not to flag every duplicate as a bug. Check
   whether a specific provider (Daraja vs. Pesapal) is retrying abnormally
   often, which usually indicates the provider isn't receiving Dunda's ack
   promptly (correlate with the `DundaReservationLatencyBreach` alert) or a
   client-side idempotency-key bug generating repeat submissions.

## Mitigation

- Latency: scale the API deployment (HPA already keys off `oban_queue_depth`
  and request latency per `infra/k8s/dunda-api-hpa.yaml`); if Postgres itself
  is the bottleneck, this is a capacity/connection-pool tuning action, not a
  code rollback.
- Duplicates: verify `Dunda.Security.Webhook` secrets haven't been rotated
  out of sync between Dunda and the provider (a provider retry storm can
  follow repeated signature-verification failures elsewhere in the pipeline,
  though `Dunda.Security.Webhook.valid?/2` itself would reject those before
  they ever reach the duplicate-detection path — check for 401s on
  `POST /api/providers/:provider/events` alongside this alert).

## Escalation

Sustained SLO breach beyond 30 minutes: page operations. Confirmed data
correctness issue (a duplicate that produced two tickets or two settlements —
should be structurally impossible per the unique constraints in
`docs/phase_5_post_release_assurance.md`): escalate as Critical immediately.
