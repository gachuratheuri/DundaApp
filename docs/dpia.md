# Data Protection Impact Assessment — Dunda ticketing platform

Status: **draft, code-grounded, pending DPO review and ODPC filing.** Every
control cited below is a live file:line reference verified against the
codebase at the time of writing, not an aspiration. Sections marked
**[EXTERNAL]** cannot be completed by this repository alone — a Data
Protection Officer has not yet been appointed (`docs/phase_3_compliance_continuity.md:53`)
and this document is the input they need, not a substitute for their sign-off.

## 1. Description of processing

**Controller**: the Dunda platform operator (organisation TBD — **[EXTERNAL]**).
**Processing purpose**: sell and validate live-event tickets in Kenya —
account creation, M-Pesa/Pesapal checkout, ticket issuance and gate
admission, resale/transfer, organiser payouts, and the fraud/audit trail
those require.
**Data subjects**: ticket buyers, resellers, event organisers and their staff,
gate-scanner operators.
**Categories of personal data processed**: identity (name, email), contact
(phone number), payment (checkout phone, payout destination, transaction
amounts/receipts), ticket (holder name, device-bound credential public key),
device (fingerprint, scanner device key), location (venue coordinates — event
metadata, not subject tracking). Full field-level detail is
`docs/data_inventory.md`, which this DPIA treats as its authoritative input
rather than duplicating.
**No special-category data** (health, biometric, religious, political,
sexual orientation) is collected by any schema in `backend/lib/dunda/**/schema`.
**Scale**: designed for national-scale Kenyan onsale traffic spikes
(`README.md` "brutal traffic spikes of an onsale moment") — this is
"large scale" processing under ODPC's systematic-monitoring threshold and
therefore in scope for a DPIA regardless of special-category status.

## 2. Necessity and proportionality

| Data element | Necessary for | Proportionality test |
|---|---|---|
| Phone (MSISDN) | M-Pesa STK push requires a phone number; it is the payment rail itself | Cannot be minimised further — it is the transaction identifier, not an optional field |
| Device fingerprint | Fraud detection on bulk-buying/bot abuse against a hard inventory cap | Collected only for checkout, not for general tracking; encrypted at rest (`user.ex:25`) |
| Device-bound ticket credential public key | Cryptographic admission proof replacing a shared-secret TOTP (`docs/phase_7_ticket_security.md`) | Public key only; the private key never leaves the holder's device secure storage — less invasive than a server-held shared secret |
| Payout destination phone | Direct statutory requirement to pay organisers via a traceable rail | Minimal: one field, encrypted, step-up-authenticated to change (`Dunda.Security.StepUp`, `backend/lib/dunda/security/step_up.ex`) |
| Ledger/order/audit retention beyond account deletion | Kenyan financial-record retention obligations and fraud-investigation need | Retention is scoped to financial/entitlement facts only; direct identifiers are pseudonymised on erasure (`Dunda.Accounts.Privacy.anonymise_user/1`) while the financial fact itself is kept — this is the proportionality balance the erasure design encodes |

No processing identified in the schema audit exceeds what checkout,
admission, payout, and statutory retention require. The scraper subsystem
(`Dunda.Scraper`) ingests **event metadata**, not personal data about
scraped-site users, and is out of DPIA scope on that basis; its risk surface
(SSRF, unbounded external fetch) is a security concern addressed in
`docs/phase_8_catalogue_scraper_ssrf.md`, not a privacy one.

## 3. Risk assessment

| # | Risk | Likelihood | Impact | Existing control | Residual risk |
|---|---|---|---|---|---|
| R1 | Phone number exfiltrated via a database breach | Low (encrypted at rest) | High | `Dunda.Vault` AES-256-GCM (`vault.ex:1-9`), key never compiled into the release (`runtime.exs:78`), key-rotation runbook (`docs/phase_11_privacy_governance.md` §Key rotation) | Low — mitigated to "attacker needs both DB and key material," and the key is externally sourced |
| R2 | Phone number exfiltrated via application logs | Medium (4 concrete unredacted call sites found and fixed this phase — §11.4) | High | `Dunda.Logging.Redactor` global filter + per-call-site fixes (`docs/phase_11_privacy_governance.md` §11.4) | Low — closed for the identified sites; new call sites are the residual risk, mitigated by the global filter as defence-in-depth |
| R3 | Cross-tenant access to another organisation's members/payouts/orders | Low (RBAC scoping is enforced in domain contexts, not only plugs — `docs/phase_2_operational_hardening.md`) | High | Organisation-scoped queries, `organisation_id` never hard-coded (audited in Phase 2) | Low |
| R4 | Forged authentication (OAuth/OTP) impersonating a data subject | Low | High | Verified OIDC (`Dunda.Auth.GoogleVerifier`), hashed/rate-limited/expiring OTP (`Dunda.Auth.Otp`) | Low |
| R5 | Erasure request cannot be honoured because financial retention overrides it, leaving the subject re-identifiable via the retained order/ticket | Medium (inherent tension between GDPR/ODPC erasure and financial-audit law) | Medium | Pseudonymisation removes every *direct* identifier (`privacy.ex:78-90`); retained rows carry only an opaque `user_id` FK to a pseudonymised account — re-identification requires the same access controls as any other financial-audit query | Medium — this is a **documented, intentional, legally-grounded residual risk**, not an oversight; it is stated in `docs/phase_3_compliance_continuity.md` and repeated here rather than hidden |
| R6 | Data-subject request missed/late, breaching the statutory response window | Medium (no deadline tracking existed before this phase) | Medium | `due_by` set on creation (`data_subject_request.ex:19`), now actively monitored by `Dunda.Workers.DsrDeadlineWorker` ([[phase_11_privacy_governance]] §11.5) | Low |
| R7 | Provider callback payload (`provider_events.payload`) retains a transient phone/receipt without field-level encryption | Medium | Medium | DB-layer access restriction, redaction on any diagnostic read; **not** field-level encrypted — see `docs/data_inventory.md` "Open item" | Medium — tracked as an open finding in `docs/phase_12_verification_observability_rollout.md`, not silently accepted |
| R8 | Key compromise (encryption or blind-index HMAC key) has no rotation path | Was High before this phase | High if unmitigated | `Dunda.Vault.KeyProvider` + dual-cipher rotation, `Dunda.Hashed.HMAC` dual-secret transition, `mix dunda.rotate_keys` ([[phase_11_privacy_governance]] §11.3) | Low — a rotation *mechanism* now exists; exercising it against a real KMS is external evidence |
| R9 | Consent withdrawn but marketing processing continues | Low (marketing notifications are the only consent-basis processing identified) | Low | `Dunda.Accounts.Consent` records grant/revocation with a version and timestamp ([[phase_11_privacy_governance]] §11.6) | Low |

## 4. Data subject rights implementation

| Right | Implementation | Reference |
|---|---|---|
| Access | `GET /api/privacy/export` | `privacy_controller.ex`, `Dunda.Accounts.Privacy.export_user/1` |
| Rectification | `PATCH /api/privacy/requests/:id` | `Dunda.Accounts.Privacy.process_rectification/3` ([[phase_11_privacy_governance]] §11.5) |
| Erasure | Controlled pseudonymisation | `Dunda.Accounts.Privacy.anonymise_user/1` |
| Portability | Same export, machine-readable JSON | `export_user/1` |
| Objection | Status-flagged, non-destructive | `Dunda.Accounts.Privacy.record_objection/2` ([[phase_11_privacy_governance]] §11.5) |

All five rights from the checklist are implemented; requests are auditable
(`Dunda.Audit.record/1` on every transition) and deadline-tracked
(`Dunda.Workers.DsrDeadlineWorker`).

## 5. Consultation and sign-off — **[EXTERNAL]**

- [ ] Data Protection Officer appointed and has reviewed this DPIA.
- [ ] ODPC registration filed and acknowledged.
- [ ] Legal counsel has confirmed the R5 pseudonymisation-over-erasure
      approach satisfies Kenyan Data Protection Act §§ retention exemptions.
- [ ] Each processor in `docs/data_inventory.md` § Processor register has a
      signed DPA on file.
- [ ] Breach-response procedure with the 72-hour ODPC notification decision
      tree is written and drilled.

This DPIA must be revisited whenever `docs/data_inventory.md` changes (new
personal-data field), a new processor is added, or a new external-facing data
flow (e.g. a new OAuth provider or SMS vendor) is introduced.
