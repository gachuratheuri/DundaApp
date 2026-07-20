# Runbook: payment/payout stuck in reconciliation

Alert: `DundaPayoutBatchStuck` (`infra/observability/alerts/business_invariants.yml`)

## Symptom

`dunda_gauge{name="payment_pending_reconciliation_count"}` > 0 — payment
intents sat in `provider_pending` for more than 10 minutes
(`Dunda.Workers.PaymentReconciliationWorker`'s `@pending_age_seconds`) and
were moved to `expired_pending_reconciliation`.

**Known gap** (tracked in
`docs/phase_12_verification_observability_rollout.md`'s findings table):
there is no equivalent age gauge for `Dunda.Organisations.PayoutBatch` yet —
this alert uses the payment-side signal as a placeholder for true payout
staleness. If you are here because an organiser payout is actually stuck,
also manually inspect `payout_batches`/`payout_items` status directly; the
alert will not yet catch that case on its own.

## First checks

1. For the payment intents named in the triggering audit trail
   (`payment_intent_transitions` with reason `"provider_pending_timeout"`):
   query the provider directly (Daraja `stk_push` query API / Pesapal
   transaction status API) for the authoritative current status — this is
   exactly the "query the provider authoritatively before settlement" path
   `docs/phase_5_post_release_assurance.md` describes for M-Pesa's
   unreliable callback signatures.
2. For payout batches: `Dunda.Organisations.Payouts` status query — is the
   batch `submitted` but never reaching `paid`, or still `pending` (never
   submitted at all — check Oban for a crashed `Dunda.Workers.PayoutWorker`
   job)?

## Mitigation

- If the provider confirms success after expiry: this is the documented
  "late success after escrow release" case — `confirmed_late` state, and
  `Dunda.Checkout.fulfil_payment_intent/1` still issues tickets normally;
  no manual intervention needed beyond confirming it actually happened.
- If the provider confirms failure or has no record: the intent is
  correctly in `expired_pending_reconciliation` → will transition onward
  per its allowed-transition graph; no manual override needed.
- If a payout batch is stuck `submitted` with no provider result after a
  reasonable window: reconcile against the B2C result callback
  (`POST /api/mpesa/b2c/result`, `Dunda.Organisations.Payouts`) — do not
  mark it `paid` without independent provider confirmation (Invariant 5:
  payout uniqueness/finality).

## Escalation

Any payout batch stuck beyond 24 hours: escalate to finance. Any payment
intent that cannot be resolved (provider has no record at all, indefinitely):
escalate to operations for manual refund initiation.
