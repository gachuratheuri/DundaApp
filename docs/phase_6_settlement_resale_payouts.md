# Phase 6 settlement, resale, refunds, and payout accounting

Phase 6 closes the remaining money-moving lifecycle gaps while preserving the
Phase 4 containment/release gate. Resale and payout operations remain
unavailable until their independent gates are approved.

## Resale protocol

1. Listing creation locks the ticket, verifies current ownership and `valid`
   status, snapshots face value, and relies on a partial unique active-listing
   index.
2. A buyer creates a normal `orders` payment intent with `kind = resale`, a
   listing foreign key, immutable amount, and idempotency key. Buyer-only
   transfer is rejected.
3. Only authoritative payment completion invokes the transfer transaction.
   It locks the order, listing, and ticket; marks the old entitlement
   transferred/revoked; mints a cryptographically distinct replacement; marks
   the listing sold conditionally; and records an idempotent seller payable
   ledger transfer.
4. Any failure rolls back the entire transfer. An unconfirmed intent can be
   cancelled to return the listing to `active`.
5. If an authoritatively confirmed payment cannot transfer, a unique durable
   full-refund intent is created and the order is held in `manual_review`; no
   buyer is left in a paid-but-unresolved state. A provider adapter must
   reconcile that intent before the refund is considered complete.

## Refund protocol

Refunds are durable intents with unique idempotency and provider references.
They use monotonic states (`pending → submitted → succeeded|failed`), lock the
order during amount validation, reject over-refunds and checked-in tickets, and
revoke tickets before recording success. Inventory restoration is deliberately
deferred to authoritative inventory reconciliation while Redis remains a
projection; a refund cannot resurrect sold capacity by itself.

Event cancellation marks the event under a row lock and enqueues a bounded,
cursor-based `EventCancellationWorker`; each order receives a unique refund
intent, so retries resume rather than duplicating requests.

## Payout protocol

`payout_batches` and `payout_items` replace the previous order-wide sweep as
the selection authority. Eligible orders are selected with
`FOR UPDATE SKIP LOCKED`, attached to one batch, and marked queued in the same
transaction. A unique order index prevents double assignment. B2C submission is
first claimed as `submitting` under a row lock; provider acceptance records
`submitted`; only the verified provider result records `paid`, while a verified
failure returns items to `unpaid` for a new, separately identifiable batch.
Ambiguous provider responses are retained in `manual_review` and never silently
retried; stale `submitting` claims are promoted to the same review state after
15 minutes, preventing duplicate funds after a crash or timeout.

Payout destinations are encrypted at rest. The migration refuses to proceed if
legacy plaintext destinations remain, requiring an audited vault backfill first.

## Required evidence before G6

- concurrent buyers produce exactly one sold listing and one replacement ticket;
- replayed provider results are idempotent;
- old ticket credentials are revoked in the authoritative ticket record;
- full and partial refund totals never exceed the captured payment;
- payout selection/retry/crash tests show one order in at most one batch;
- provider acceptance, final success, final failure, timeout, and callback loss
  all converge without duplicate funds;
- payout destination encryption and the plaintext-backfill audit are recorded.
