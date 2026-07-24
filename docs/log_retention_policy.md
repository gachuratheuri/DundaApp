# Log retention and access-control policy

This document covers **application/infrastructure logs** — stdout/stderr from
the BEAM release, ingested by whatever log pipeline the operator runs. It is
distinct from `Dunda.Audit` (`backend/lib/dunda/audit.ex`), which is a
database-resident, append-only, immutable business/security record with no
automated deletion (`docs/phase_3_compliance_continuity.md`); this policy
does not change that.

## What is logged

`Dunda.Logging.Redactor` (`backend/lib/dunda/logging/redactor.ex`) is
installed as a global `:logger` primary filter at boot
(`Dunda.Application.start/2`) and redacts:

- structured log metadata (`Logger.metadata/1`, report-style log calls) whose
  key name matches a sensitive-key list (password, token, OTP, receipt,
  MSISDN/phone, bearer, JWT, security credential, etc.);
- bearer tokens, JWTs, and Kenyan MSISDNs appearing in binary values passed
  through `Dunda.Logging.Redactor.redact/1` at call sites that must
  `inspect/1` a provider payload (`Dunda.Billing.Pesapal.HTTP`,
  `Dunda.Payments.Daraja.HTTP`,
  provider callback controllers).

This is defence-in-depth, not a guarantee against every possible future log
call embedding sensitive data in an interpolated string the filter cannot
parse — code review remains the primary control for new log call sites (see
`docs/phase_12_verification_observability_rollout.md` § Security tests,
`Dunda.Logging.Redactor` test suite).

Correlation metadata (`request_id` — set automatically by `Plug.RequestId`;
`payment_intent_id`, `checkout_request_id`, `order_tracking_id`,
`organiser_user_id` — set explicitly at the point each becomes known, see
`checkout_controller.ex`, `mpesa_controller.ex`, `ipn_controller.ex`,
`organiser_auth_plug.ex`) is **not** redacted; these are opaque identifiers,
not personal data, and are required for incident correlation.

## Retention

| Log tier | Retention | Rationale |
|---|---|---|
| Application logs (stdout/stderr, non-error) | 30 days | Operational debugging window; no statutory retention need |
| Application error/warning logs | 90 days | Incident investigation window |
| Access logs (HTTP request line, status, latency — no body) | 90 days | Security/abuse investigation |
| Audit events (`Dunda.Audit`, database) | Indefinite, append-only | Financial/security evidence — out of scope for this policy, see above |

These durations are the **policy this codebase's redaction and metadata
design assumes**; enforcing them is the responsibility of whatever log
pipeline/SIEM the operator runs (Loki, CloudWatch Logs, Datadog, etc.) — this
repository does not ship one (`docs/phase_9_infrastructure_resilience.md`
notes infrastructure choices are operator-selected). **External evidence
required**: configure the chosen pipeline's retention/expiry to match this
table and document the pipeline choice here.

## Access control

- Production logs must be restricted to on-call engineers and the
  security/privacy roles defined in `Dunda.ReleaseApproval`
  (`backend/lib/dunda/release_approval.ex`) — nobody else, by default.
- Any log-query tool with full-text search must be assumed to expose
  whatever the redaction filter missed; access to it is therefore
  access to a *residual* PII risk surface, not a zero-risk one, and should be
  scoped and audited accordingly.
- Log access itself should be logged by the pipeline (external evidence —
  this repository has no visibility into or control over a third-party log
  platform's own access-audit trail).

## Keeping this honest

If a new log call site is added that inspects a provider payload, request
body, or any field listed in `docs/data_inventory.md`, it must route through
`Dunda.Logging.Redactor.redact/1` (or avoid logging the raw value entirely).
`docs/phase_12_verification_observability_rollout.md` § Security tests
includes a secret-leakage test asserting the redactor's coverage; it does not
and cannot assert that every future call site uses it — that remains a code
review responsibility.
