# Phase 3 compliance, continuity, and scale readiness

Phase 3 operationalises the remaining production obligations identified by the
technical audit. It is deliberately conservative: financial evidence and audit
events are protected from automated deletion, and no payment route is enabled
by this phase alone.

## Implemented controls

- Data-subject request primitives support access/export and controlled
  pseudonymisation. Erasure removes direct account identifiers and secrets while
  retaining orders, tickets, ledger entries, scans, and audit references needed
  for statutory and fraud investigation.
- Export output is minimised and excludes password hashes, entitlement tokens,
  encrypted contact fields, and device secrets.
- Authenticated `/api/privacy/requests` and `/api/privacy/export` endpoints
  expose the access/portability workflow without exposing pseudonymisation as
  an unauthorised self-service destructive operation.
- `mix dunda.phase_3_retention` provides a dry-run retention report. Execution
  requires an explicit confirmation token, remains blocked during Phase 0, and
  deletes only read notifications older than 365 days. Orders, tickets, ledger
  entries, and audit events are protected.
- Ticket responses no longer contain a fabricated holder identity.
- Mobile checkout generates and propagates an idempotency key compatible with
  the server-side reservation invariant.

## Retention and privacy policy

| Dataset | Automated policy | Rationale |
|---|---|---|
| Ledger entries | Never automated-delete; retain at least statutory period | Financial evidence |
| Orders and tickets | Never automated-delete | Settlement, entitlement, fraud, and support evidence |
| Audit events | Append-only; no automated deletion | Security and regulatory evidence |
| Data-subject requests | Retain request/status history | Accountability and statutory response evidence |
| Read notifications | Delete after 365 days when read | Non-essential derived data |
| Encrypted contact/device fields | Remove only through approved pseudonymisation | Data minimisation |

Preview before execution:

```text
mix dunda.phase_3_retention
```

Execution requires an operator-controlled confirmation:

```text
$env:DUNDA_RETENTION_CONFIRM='I_UNDERSTAND_PHASE_3_RETENTION'
mix dunda.phase_3_retention --execute
```

## Required external evidence

1. Complete ODPC registration, DPIA, DPO appointment, privacy notice, and breach
   response procedure with the 72-hour notification decision tree.
2. Test export and pseudonymisation against legal holds, financial disputes,
   fraud investigations, and re-identification resistance.
3. Perform PostgreSQL and Redis restore drills; record RPO, RTO, data loss, and
   reconciliation outcomes.
4. Run onsale load tests against the atomic inventory path, including Redis
   saturation, pod eviction, callback duplication, and database replica lag.
5. Validate HPA/PDB behaviour and pre-warming decisions with observed capacity
   curves, not the static defaults alone.
6. Obtain independent privacy, security, and financial-control sign-off before
   changing containment or enabling any provider callback.
