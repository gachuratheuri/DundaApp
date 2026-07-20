# Phase 11 — privacy, compliance, auditability, and data governance

Phase 11 turns the Phase 3 compliance primitives
(`docs/phase_3_compliance_continuity.md`) into a complete data-governance
program: a verified data inventory, a DPIA, encryption of the remaining
plaintext contact fields, a real key-rotation mechanism, log redaction, a
complete (all five rights) DSR workflow with deadline monitoring, consent
records, and an automated backup-retention check. Like every prior phase,
this is additive: it does not lift Phase 0 containment, and no previously
disabled route is re-enabled by this work alone.

## Implemented controls

### Data inventory, classification, and DPIA (§11.1)

- `docs/data_inventory.md` — every personal-data-bearing column across
  `Dunda.Accounts.User`, `Dunda.Billing.Order`, `Dunda.Checkout.PaymentIntent`,
  `Dunda.Organisations.{Organisation,Payout}`, `Dunda.Ticketing.{Ticket,ScannerDevice}`,
  `Dunda.Events.Event`, `Dunda.Audit.Event`, and `Dunda.Checkout.ProviderEvent`,
  each mapped to category, sensitivity, encryption status, lawful basis,
  purpose, and retention rule — verified against the live schema files, not
  aspirational. Includes a processor register (Daraja, Pesapal, Google OAuth,
  SMS provider, cloud/hosting).
- `docs/dpia.md` — a full DPIA: processing description, necessity/
  proportionality test, a nine-item risk matrix with file:line-cited
  controls and residual risk, DSR-rights-implementation table, and an
  explicit **[EXTERNAL]** consultation/sign-off section (DPO appointment,
  ODPC registration, processor DPAs, breach-response procedure) that this
  repository cannot complete on its own.

### Encryption of remaining plaintext contact fields (§11.2)

`Dunda.Billing.Order.phone` and `Dunda.Checkout.PaymentIntent.phone` were
plaintext; `Dunda.Organisations.Organisation.support_email` was reviewed and
left plaintext deliberately (it is customer-facing public contact
information, not a secret — recorded in `docs/data_inventory.md`, not an
oversight). Migration `phase11_encrypt_contact_fields.exs` follows the exact
precedent set by `mpesa_phone_encrypted`
(`20260724000001_phase6_settlement_resale_payouts.exs`): it raises if
legacy plaintext rows exist (forcing an audited backfill first — this
reference implementation has no production data yet), renames the column to
`phone_encrypted` (`Dunda.Encrypted.Binary`), and every internal read site
(`Dunda.Checkout`, `Dunda.Billing`, `Dunda.Market`, `Dunda.Workers.PaymentSubmissionWorker`)
was updated to match.

### Key management (§11.3)

- `Dunda.Vault.KeyProvider` — a behaviour (mirroring the existing
  `Dunda.Payments.Daraja`/`Dunda.Billing.Pesapal` adapter pattern) that
  `config/runtime.exs` resolves key material through, instead of calling
  `System.fetch_env!/1` directly. `Dunda.Vault.KeyProvider.Env` is the only
  adapter with real credentials wired up in any environment this codebase
  has run in; a cloud-KMS-backed adapter (AWS KMS / GCP Cloud KMS / Vault
  Transit envelope-decrypting a wrapped DEK at boot) can be added later by
  implementing the same behaviour, with zero call-site churn. This was a
  deliberate, user-confirmed decision: committing to a specific cloud
  provider with no real credentials to test against would have produced
  unverifiable code; the behaviour seam is the honest middle ground.
- **Key rotation runbook**: `ENCRYPTION_KEY_VERSION` (default `1`) makes the
  Vault cipher tag an explicit generation number, not an "is rotation
  active" flag — this matters because the tag must always match what is
  actually persisted, in steady state as much as mid-rotation. To rotate:
  bump `ENCRYPTION_KEY_VERSION`, set the new `ENCRYPTION_KEY`, set
  `ENCRYPTION_KEY_PREVIOUS` to the outgoing key, deploy, then run
  `mix dunda.rotate_keys --reencrypt` (re-saves every `Dunda.Encrypted.Binary`
  field under the new key) and/or `--blind-index` (recomputes
  `User.phone_msisdn_hash` from the independently-encrypted plaintext —
  never from the old hash, which is one-way, so no dual-secret verification
  window is needed for the blind index at all). The task is idempotent;
  re-run until `migrated: 0, failed: 0` before removing
  `ENCRYPTION_KEY_PREVIOUS`. There is deliberately no "how many rows are
  still on the old generation" report — Cloak's on-disk ciphertext format is
  not a public contract this codebase should parse by hand
  (`Dunda.Vault.Rotation` moduledoc).
- Separation from application config: keys are resolved via the
  `KeyProvider` seam at boot, never compiled into the release
  (`config/runtime.exs`), consistent with the pre-existing pattern for every
  other production secret in this file.

### Log redaction and correlation metadata (§11.4)

- `Dunda.Logging.Redactor` — an `:logger` primary filter installed in
  `Dunda.Application.start/2` before any other child starts, redacting
  structured log metadata by sensitive-key-name match (extends
  `Dunda.Audit`'s `@sensitive_keys` list), plus a `redact/1` helper applying
  a best-effort regex scrub (bearer/JWT tokens, Kenyan MSISDNs) to binary
  values. This is defence-in-depth, not the primary control — the primary
  control is the four concrete unredacted-logging call sites this phase
  fixed directly: `Dunda.Workers.MpesaPoller` (logs a receipt SHA-256
  fingerprint instead of the raw receipt), `Dunda.Billing.Pesapal.HTTP` and
  `Dunda.Payments.Daraja.HTTP` (redact the provider response body before
  `inspect/1`), `DundaWeb.MpesaController` (redacts the inspected STK
  callback payload).
- Correlation metadata: `payment_intent_id` (`checkout_controller.ex`),
  `checkout_request_id` (`mpesa_controller.ex`), `order_tracking_id`/
  `merchant_reference` (`ipn_controller.ex`), `organiser_user_id`
  (`organiser_auth_plug.ex`) are set via `Logger.metadata/1` at the point
  each becomes known in the request process — this satisfies both this
  phase's log-redaction goal and Phase 12's observability requirement for
  correlation IDs in structured logs; it was built once and is referenced
  from both docs. `request_id` was already set automatically by
  `Plug.RequestId` (`endpoint.ex`) — no change needed there.
- `docs/log_retention_policy.md` — retention duration per log tier,
  access-control statement, and the explicit boundary: enforcing the stated
  retention is the responsibility of whatever log pipeline the operator
  runs (external evidence — this repository ships no log shipper).

### Complete DSR workflow (§11.5)

All five rights, not just access/erasure:

| Right | Implementation |
|---|---|
| Access | `GET /api/privacy/export` → `Dunda.Accounts.Privacy.export_user/1` (pre-existing) |
| Rectification | `PATCH /api/privacy/requests/:id` → `Dunda.Accounts.Privacy.process_rectification/3` — deliberately narrow (display name only; email/phone are also authentication identity and go through their own reverification flows) |
| Erasure | `Dunda.Accounts.Privacy.anonymise_user/1` (pre-existing) |
| Portability | Same export as access |
| Objection | `PATCH /api/privacy/requests/:id` → `Dunda.Accounts.Privacy.record_objection/3` — a durable, auditable status change and note, never an automated deletion |

`DundaWeb.PrivacyController.update_request/2` dispatches by the request's
**own recorded** `request_type` (never client-supplied), so a client cannot
reclassify their request to reach a different code path. Every DSR request
now moves through an explicit `received -> in_progress -> completed |
rejected` state machine (`Dunda.Accounts.Privacy.transition_status/3`,
mirroring `Dunda.Checkout.PaymentIntent`'s transition-graph style), audited
on every change. `Dunda.Workers.DsrDeadlineWorker` runs hourly (regardless of
Phase 0 containment — privacy-deadline monitoring is not a guarded
external-effect path), gauging current overdue/due-soon counts
(`Dunda.Observability.gauge/2`) and auditing an event when any request is
overdue. `mix dunda.dsr_transition` is the operator-facing tool for
completing `access`/`erasure`/`portability` requests once the corresponding
action was actually taken outside this system (e.g. delivering an export).

### Consent records (§11.6)

`Dunda.Accounts.Consent` (`consents` table, one active grant per
`(user_id, purpose)` enforced by a partial unique index) with
`Dunda.Accounts.record_consent/3`, `revoke_consent/2`, `active_consent?/2`.
Revocation never deletes the historical row — the grant/revocation history
is itself the accountability evidence a DPIA needs. Scoped honestly: this
codebase's checkout/ticketing processing is contract-necessity, not
consent-based, per `docs/data_inventory.md`'s lawful-basis column — the only
identified consent-basis purpose today is optional marketing notifications,
so this ships as a ready, tested primitive rather than a feature with no
current caller.

### Backup-deletion/retention automated check (§11.7)

`test/dunda/retention_test.exs` (previously absent) asserts
`Dunda.Retention.execute/1` never touches ledger/order/ticket/audit rows and
is blocked during containment. `mix dunda.backup_retention_check
--capture-baseline`/`--verify` (documented in `infra/backup/README.md`)
turns the "quarterly restoration drills must demonstrate no statutory
record loss" requirement from a manual eyeball check into an
exit-code-driven one, reusing `Dunda.Retention.preview/1`'s protected-table
counts rather than duplicating that list.

## Required external evidence

1. DPO appointment, ODPC registration, and legal sign-off on `docs/dpia.md`
   (§5 — explicitly marked **[EXTERNAL]** in that document).
2. Signed DPAs for every processor in `docs/data_inventory.md`'s processor
   register.
3. A named log pipeline configured to the retention durations in
   `docs/log_retention_policy.md`.
4. Exercising `mix dunda.rotate_keys` against a real secret manager /
   eventual KMS adapter, and a documented rotation cadence approved by
   security.
5. A quarterly restoration drill run with `mix dunda.backup_retention_check`
   wired into the actual backup/restore procedure, not just described.

## Exit gate G11

- [x] Every personal-data field has an owner, purpose, retention rule, and
      security control documented in `docs/data_inventory.md`.
- [x] DSR workflows (all five rights) operate end to end, are auditable, and
      are deadline-monitored.
- [ ] Logs and backups no longer undermine application-level encryption —
      **partially met**: redaction and the retention-check tooling exist;
      an actual configured log pipeline and exercised backup/restore cycle
      are external evidence (above), not yet demonstrated.

G11 is not fully closeable from source code alone — the checked boxes above
are what this repository can prove; the unchecked one requires the external
evidence items listed.
