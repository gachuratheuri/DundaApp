# Runbook: data-subject request past its statutory deadline

Alert: `DundaDsrDeadlineOverdue` (`infra/observability/alerts/business_invariants.yml`)

## Symptom

`dunda_gauge{name="dsr_requests_overdue"}` > 0 — one or more
`Dunda.Accounts.DataSubjectRequest` rows are past `due_by` (30 days from
creation) without reaching `completed`/`rejected`. Set hourly by
`Dunda.Workers.DsrDeadlineWorker` (`docs/phase_11_privacy_governance.md` §11.5).

## First checks

1. Identify the overdue request(s): the triggering audit event
   (`Dunda.Audit`, action `"privacy.dsr_deadline_overdue"`) lists the
   specific `request_ids` in its metadata.
2. `Repo.get(Dunda.Accounts.DataSubjectRequest, id)` (or a read-only console
   query) to see `request_type` and `status` — is it stuck at `"received"`
   (never triaged) or `"in_progress"` (triaged but not completed)?

## Mitigation

- `access`/`portability`: complete via `Dunda.Accounts.Privacy.export_user/1`
  and deliver the export to the data subject through the organisation's
  documented secure-delivery channel (external process — this repository
  only produces the export payload), then
  `mix dunda.dsr_transition --id <id> --status completed`.
- `erasure`: run the controlled pseudonymisation
  (`Dunda.Accounts.Privacy.anonymise_user/1`), then transition to completed.
- `rectification`/`objection`: these are meant to self-complete via
  `PATCH /api/privacy/requests/:id` when the data subject acts — an overdue
  one here means the subject was never notified their request needs a
  follow-up action from them, or the request needs an operator to intervene
  via `mix dunda.dsr_transition`.
- If more time is genuinely needed and this is within your jurisdiction's
  permitted extension: `mix dunda.dsr_transition --id <id> --status in_progress --note "extension reason, on file with <reference>"`.
  This does not reset `due_by` — the alert stays active by design
  (statutory deadlines are not extended by internal process alone; consult
  legal/privacy counsel before treating a jurisdiction-specific extension as
  closing this alert).

## Escalation

Any request overdue by more than 7 days beyond `due_by`: escalate to the
privacy/DPO role (`Dunda.ReleaseApproval`'s `privacy` role,
`docs/phase_12_verification_observability_rollout.md` §12.12) — a missed
statutory deadline is a compliance incident, not only an operational one.
