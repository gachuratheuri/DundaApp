# Phases 3–5 checkout, inventory, settlement, and reconciliation

The new checkout path is additive and remains behind the Phase 0/4 release
gate. It does not activate legacy M-Pesa or Pesapal flows merely by migrating
the schema.

## Phase 3: one aggregate

`quotes` are server-priced, short-lived, signed records bound to the user,
event, tier, quantity, currency, price version, and expiry. A client submits
only `quote_id`, phone, and an `Idempotency-Key`.

`payment_intents`, `payment_attempts`, `provider_events`, line items, ticket
batches, and outbox events provide provider-neutral durable state. State changes
are versioned and recorded in `payment_intent_transitions`; the database trigger
rejects invalid transitions even if application code is bypassed.

## Phase 4: PostgreSQL inventory authority

`inventory_pools` stores capacity, reserved quantity, sold quantity, and a
version. Reservation occurs in the same PostgreSQL transaction as the payment
intent, line item, and provider-submission outbox event. The conditional update
requires `capacity - reserved - sold >= quantity` while holding the pool row.

Redis is reconstructed from these rows by `InventoryReconciliationWorker` and
is not required to reconstruct business truth. Expiry locks the intent,
reservation, and pool; uncertain provider states remain `uncertain` and are not
released automatically.

## Phase 5: settlement and fulfilment

Provider events are durably acknowledged and deduplicated before processing.
Provider correlation, receipt, and amount are checked before confirmation.
`PaymentFulfilmentWorker` locks the intent and reservation, consumes reserved
inventory, writes a balanced settlement journal, creates one ticket batch and
exactly the paid quantity of tickets, then marks the intent fulfilled and emits
notification outbox work in one transaction.

The journal is append-only and uses balanced debit/credit lines. A deferred
PostgreSQL constraint trigger rejects unbalanced transactions; account balances
are disposable projections. Reconciliation workers preserve provider
correlation state, detect aged pending payments, and route missing settlement
journals to manual review.

Refunds are represented as durable `refund_pending` intents and outbox work.
The refund worker deliberately does not fabricate provider success: a provider
refund adapter and verified terminal callback are required before `refunded`
can be recorded.

## Operational prerequisites

- Configure `QUOTE_SIGNING_SECRET` in every non-test environment.
- Run the additive migration and reconcile seeded inventory pools against
  existing tickets before requesting release approval.
- Provide provider-specific signed callback secrets where supported.
- Implement and test the selected provider refund adapter before enabling
  automatic fulfilment-compensation refunds.
- Execute the PostgreSQL/Oban/Redis concurrency and fault-injection suite before
  lifting containment.
