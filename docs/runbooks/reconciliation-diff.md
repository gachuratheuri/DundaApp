# Runbook: unreconciled confirmed payment

Alert: `DundaUnreconciledPayments` (`infra/observability/alerts/business_invariants.yml`)

## Symptom

`dunda_gauge{name="reconciliation_diff_count"}` > 0 — a payment intent in
state `confirmed`, `fulfilled`, or `confirmed_late` has no matching
`journal_transactions` row with reference `"settlement:<intent_id>"`. Set
every run of `Dunda.Workers.FinancialReconciliationWorker`. The root-plan
SLO is literally zero — this alert firing at all means the invariant
"every confirmed payment reconciles to fulfilment, refund, or manual review"
(Phase 5 exit gate) has a live counterexample.

## First checks

1. `Dunda.Workers.FinancialReconciliationWorker` itself already moves the
   offending intent(s) to `manual_review` with reason
   `"settlement_journal_missing"` — query `payment_intent_transitions` for
   that reason to find exactly which intents and when.
2. Check whether `Dunda.Checkout.fulfil_payment_intent/1` ever ran for that
   intent: `payment_intent_transitions` should show a
   `"tickets_issued"`-reasoned transition if fulfilment completed. If
   fulfilment never ran, check the outbox
   (`Dunda.Checkout.OutboxEvent`, event_type
   `"payment_fulfilment_requested"`) for that intent — is it still
   `"pending"` (dispatcher backlog — check `oban_queue_depth`) or was it
   dispatched but the fulfilment job itself failed (check Oban job history)?

## Mitigation

- If fulfilment is simply delayed (outbox event pending, queue backlog):
  this resolves once the backlog drains — confirm
  `Dunda.Workers.OutboxDispatcherWorker` and
  `Dunda.Workers.PaymentFulfilmentWorker` are both running and not crash-
  looping.
- If fulfilment genuinely failed (e.g. `:inventory_unavailable_for_fulfilment`
  in `Dunda.Checkout.fulfil_locked!/1` — the reservation's inventory was
  released or oversold between confirmation and fulfilment, which should be
  structurally prevented by `fulfil_locked!/1`'s own guard): this is now in
  `manual_review` and requires an operator decision — issue replacement
  inventory (if available) or initiate a refund via
  `Dunda.Billing.Refunds`. **Never** manually write a settlement journal
  entry to make the alert go away without confirming tickets were actually
  issued — that would break Invariant 4 (ledger conservation) by recording
  money movement for a purchase the customer didn't receive.

## Escalation

Any diff count > 0 for more than 15 minutes: page finance + operations
immediately. This is a Critical financial-integrity alert, not a
best-effort one.
