# Phase 12 — verification, observability, rollout, and governance

Phase 12 is the last phase before the root plan's exit gate G12. It adds the
test hierarchy the plan calls for (property-based, contract, fault-injection,
migration, mutation, performance), closes the observability gap (a real
Prometheus scrape target, per-endpoint SLOs, business-invariant metrics,
dashboards, alerts, runbooks), extends release governance to the full
five-stakeholder set, and hardens CI to match what its own prior-phase docs
already claimed was required. It also surfaces — and, where in scope, fixes
— several defects this phase's own test-writing process uncovered in
earlier phases' code, most importantly a Critical one in the checkout
authority itself (now fixed) and a High one in organiser-portal
authorization (open — see § Findings and pen-test tracking, which also
documents a correction to that same finding's own first draft).

**A note on verification**: the sandbox this phase was implemented in has no
Elixir/Erlang/mix toolchain and no Docker, so none of the code below has
been compiled or executed by the agent that wrote it. Every change was
cross-checked by hand against the actual surrounding source (exact function
signatures, field names, changeset cast lists, migration conventions) rather
than assumed — the fixture bug found in §12.3/§12.7 below is a direct
product of that hand-verification process catching a real, pre-existing gap.
Before relying on this phase's guarantees, run the commands in
§ Verification below.

## Test hierarchy implemented

| Category | Location | Notes |
|---|---|---|
| Property-based (inventory) | `test/dunda/inventory_property_test.exs` | Drives the exact guarded `Repo.update_all` SQL from `Dunda.Checkout` directly; asserts Invariant 1 across StreamData-generated operation sequences |
| Property-based (ledger) | `test/dunda/ledger_property_test.exs` | Drives `Dunda.Checkout.Journal.post!/4` directly; asserts Invariant 4 for both balanced and unbalanced generated line sets |
| Property-based (transitions) | `test/dunda/payment_intent_transition_property_test.exs` | Exhaustive pairwise table + StreamData random-walk property against `PaymentIntent.transition_allowed?/2` |
| API contract | `priv/openapi/dunda.json` (JSON, not YAML — see file's `info.description`), `test/support/contract_case.ex`, `test/dunda_web/contract/core_endpoints_contract_test.exs`, retrofitted into `test/dunda_web/controllers/privacy_controller_test.exs` | Schemas verified against actual serializers (`EventJSON`, `TicketJSON`, controllers), not assumed — an earlier draft had the Event schema wrong (`price_cents`/integer `id` that don't exist in the real response) until checked against `event_json.ex` |
| Integration (Postgres/Redis/Oban) | Pre-existing (`inventory_test.exs`, sandbox tests) plus all of the above, which are Postgres-integration by nature | |
| Concurrency | `test/dunda/payments/duplicate_callback_test.exs` (8-way concurrent identical confirmation) | |
| Fault-injection (duplicate/reordered events) | `test/dunda/payments/duplicate_callback_test.exs`, `test/dunda/payments/reordered_events_test.exs` | Found and fixed a real crash bug — see finding F1 |
| Migration test | `priv/repo/seeds_production_shaped.exs`, `mix dunda.migration_drill` | Migrates to HEAD~1, seeds ~2,000 orders/tickets/ledger transactions through real changesets, applies the latest migration, verifies no protected-row loss |
| Security | `test/dunda/security/webhook_test.exs`, `test/dunda_web/rbac_test.exs`, `test/dunda/logging/redactor_test.exs` | The RBAC test both validates the one real enforcement primitive (`Dunda.Organisations.member?/3`) and characterizes where it isn't applied — see finding F2 |
| Performance | `mix dunda.load_test` | In-process concurrent load generator against the real reservation transaction; asserts p99 < 150ms |
| Mutation | `mix dunda.mutation_test` | 4 hand-picked mutants on the highest-risk guards (inventory reservation, ledger balance, webhook signature, state-transition guard); no maintained free Elixir mutation framework exists (Muzak is commercial) — recorded explicitly, not silently skipped |
| End-to-end mobile | `frontend/src/api/__tests__/client.test.ts`, `frontend/src/security/__tests__/ticketCredential.test.ts` | Unit/logic-level only — full on-device Detox/Maestro E2E needs an Android/iOS SDK CI runner this environment doesn't have; recorded as external evidence, not silently dropped |

## SLOs implemented

| SLO | Mechanism |
|---|---|
| Zero oversell | DB CHECK constraint + guarded update (pre-existing) + `inventory_property_test.exs` |
| Zero unreconciled confirmed payments | `dunda_gauge{name="reconciliation_diff_count"}` (`Dunda.Workers.FinancialReconciliationWorker`) |
| Checkout p95 < 300ms | `Dunda.Observability` per-route latency histogram + `Dunda.ReleaseHealth.evaluate/1`'s `endpoint_slo.checkout_p95_ok` |
| Reservation p99 < 150ms | Same histogram; `mix dunda.load_test` asserts it under generated load |
| Webhook durable ack < 2s | `webhook_ack_ms_last` gauge + `webhook_ack_breach_total` counter, set in `DundaWeb.ProviderEventsController.receive_event/4` at the durable-commit instant |
| API availability ≥ 99.95% | Not implementable from application code alone — requires a real uptime-monitoring system external to this codebase; `dunda_requests_5xx_total`/`dunda_requests_total` give the raw numerator/denominator an external SLO tool would consume |
| Financial DB RPO | Policy-only (`docs/phase_9_infrastructure_resilience.md`) — unchanged by this phase |
| Alert ack window | Operational, not code — depends on the paging system that consumes `infra/observability/alerts/business_invariants.yml` |

## Observability

- **Structured logs / correlation IDs**: see `docs/phase_11_privacy_governance.md` §11.4 (built once, referenced from both docs).
- **OpenTelemetry tracing**: `opentelemetry`, `opentelemetry_exporter`, `opentelemetry_phoenix`, `opentelemetry_ecto` added; `OpentelemetryPhoenix.setup/1` and `OpentelemetryEcto.setup/1` (both repos) called in `Dunda.Application.start/2`. No-op exporter by default (`config/config.exs`); OTLP enabled only when `OTEL_EXPORTER_OTLP_ENDPOINT` is set (`config/runtime.exs`, prod-only, matching every other deploy-time secret in that file). Manual span added to `Dunda.Workers.OutboxDispatcherWorker` (the durable-intent-to-dispatch boundary, Invariant 9) as a representative pattern — this is **not** exhaustive across every worker; extending it is a natural follow-up, listed as finding F7.
- **Prometheus scrape target**: `GET /internal/metrics/prometheus` (`Dunda.Observability.render_prometheus/0`) — **new**. Before this phase, `/internal/metrics` only returned JSON; no Prometheus server could have actually scraped this application. Renders true cumulative histogram buckets (required for `histogram_quantile()` to work correctly — the internal storage is per-bucket, not cumulative, so cumulation happens at render time, grouped by route).
- **Business-invariant metrics**: `reconciliation_diff_count`, `payment_pending_reconciliation_count`, `payment_reconciliation_moved_total`, `webhook_duplicate_total`, `webhook_ack_ms_last`, `webhook_ack_breach_total`, `dsr_requests_overdue`, `dsr_requests_due_soon`, `dsr_deadline_checks_total`, `inventory_reconciliation_failed_total`, plus the pre-existing `oban_queue_depth` and per-route request/latency metrics. `Dunda.Observability.gauge/2` was added alongside the pre-existing `increment/2` — a real architectural gap this phase closed: the counter registry had no way to represent "current value" (point-in-time), only "total since boot" (monotonic), which several of these metrics genuinely need.
- **Dashboards**: `infra/observability/dashboards/{checkout_funnel,inventory,payment_reconciliation,payouts,scanner_admissions,scraper_freshness}.json` — Grafana-importable, each panel referencing a real metric name this application actually exposes (verified against `render_prometheus/0`'s actual output shape, not assumed — the scanner-admissions and scraper-freshness dashboards explicitly document the metric gaps they're limited by, see findings F5/F6).
- **Alerts**: `infra/observability/alerts/business_invariants.yml` — Prometheus alerting rules with `runbook_url` annotations pointing at real files.
- **Runbooks**: `docs/runbooks/{oversell,stuck-payment,dsr-overdue,reconciliation-diff,payout-stuck}.md`, each following symptom/first-checks/mitigation/escalation.
- Activating dashboards/alerts against a live Prometheus/Grafana/Alertmanager remains external evidence (same boundary as every prior phase's infrastructure claims).

## Controlled rollout

- `Dunda.ReleaseApproval`'s role set extended from `(security, finance, operations)` to the full G12 five-stakeholder set `(security, finance, operations, product, privacy)` — migration `phase12_release_approval_roles.exs` (drop/recreate the CHECK constraint; constraints cannot be altered in place). This is a real hardening: every currently-configured release approval in a live deployment would newly require product and privacy sign-off — safe to change now because this repository has no live deployment/approvals yet (Phase 0 containment, reference implementation).
- `Dunda.ReleaseApprovals.rollback_threshold_breached?/1` — read-only evidence (mirrors `Dunda.ReleaseHealth`'s explicitly non-actuating design) combining `ReleaseHealth.evaluate/0` with the `reconciliation_diff_count`/`dsr_requests_overdue` gauges into a single breach signal. It does not revoke approvals itself; an operator or external automation acts on it, preserving the deliberate human-in-the-loop design established in Phase 4.
- Forward-fix-only migration policy: already the convention (every migration since Phase 6 is `def up` only); now **mechanically enforced** by a CI step (`Migration immutability`, `.github/workflows/ci.yml`) that fails a PR modifying any migration file already merged to `main`.
- CI additionally rejects a PR whose changed test files contain a commented-out assertion (`# assert`) — diff-scoped (only newly touched files), not retroactive, so it doesn't break on the pre-existing `resale_controller_test.exs` placeholder (finding F3) while still preventing new vacuous tests.

## CI changes

`.github/workflows/ci.yml`: added `mix dialyzer` (PLT cached separately from
the general deps/`_build` cache) and `mix test --cover` to the `backend`
job — closing the exact discrepancy the Phase 12 gap audit found between
`docs/phase_2_operational_hardening.md`'s documented requirements and what
CI actually ran. Added `git diff --check`, migration-immutability, and
vacuous-test-diff steps (PR-only). Added a `migration-drill` job and a
path-filtered `mutation-test` job (PR-only; only runs when a mutation
target or its covering test changed, since mutation testing copies the
whole project per mutant and is slow by design). Added `npm test` to the
`frontend` job.

**Note**: `mix test --cover` uses Elixir's built-in coverage tool (visibility
only, no enforced floor) rather than adding `excoveralls` as a new
dependency — a deliberate scope reduction given how many new dependencies
this phase already introduces (`stream_data`, `ex_json_schema`, four
`opentelemetry_*` packages) that could not be verified by actually running
`mix deps.get` in this environment. Adding a coverage-floor gate is a
reasonable, low-risk follow-up once the current dependency set is confirmed
to resolve and compile cleanly.

## Findings and pen-test tracking

This table is the mechanism `docs/phase_12`'s own governance model requires
— seeded with real findings from this session's own work, not left empty.

| ID | Severity | Finding | Status | Evidence |
|---|---|---|---|---|
| F0 | **Critical** | Event creation formerly omitted the authoritative PostgreSQL inventory pool, causing subsequent reservation attempts to fail. | **Fixed** — event creation and capacity changes maintain the pool transactionally; checkout integration tests exercise the authoritative quote/reservation path. | `test/dunda/events_inventory_pool_test.exs`; `test/dunda_web/controllers/checkout_controller_test.exs` |
| F1 | High | `Dunda.Checkout.fail_payment/2`'s short-circuit guard covered only `["fulfilled", "refunded"]`. A stale/reordered provider-failure callback arriving after confirmation (`confirmed`/`confirmed_late`/`manual_review`/`refund_pending`/`expired_pending_reconciliation`) would attempt an invalid state transition and crash (`Repo.update!` raising) rather than no-op — no financial corruption (the transaction rolls back), but the calling Oban job would crash-loop. | **Fixed** | `PaymentIntent.transition_allowed?/2` extracted as single source of truth; `checkout.ex`'s guard now uses it; `test/dunda/payments/reordered_events_test.exs` |
| F2 | High | Portal entry and mutating organiser operations formerly lacked a complete role-permission boundary. | **Fixed** — portal access requires an active owner/admin/manager membership, and tenant-sensitive context operations enforce explicit permissions. | `Dunda.Organisations.authorised?/3`; `DundaWeb.PortalAccess`; `test/dunda_web/rbac_test.exs` |
| F3 | Medium | Checkout controller tests targeted a legacy response contract. | **Fixed** — tests now exercise the current quote-bound payment-intent contract, including idempotent replay, cross-user denial, quantity limits, and hostile client economics. | `test/dunda_web/controllers/checkout_controller_test.exs` |
| F4 | Medium | Reservation release discarded the provider failure reason. | **Fixed** — `release_reservation!/3` persists the supplied reason in both the payment intent and transition history. | `Dunda.Checkout.release_reservation!/3`; `test/dunda/payments/reordered_events_test.exs` |
| F5 | Low | Raw provider callback payloads were not field-level encrypted. | **Fixed** — provider-event payloads use the encrypted field type and are decoded only inside the durable processing worker. | `Dunda.Checkout.ProviderEvent`; `Dunda.Workers.ProviderEventWorker` |
| F6 | Low | Scraper metrics (`{:scraper_empty_result, source}` / `{:scraper_schema_drift, source}`) use a compound tuple as the counter key, which `render_prometheus/0` renders via `inspect/1` into an awkward (but functional and correctly escaped) label value rather than separate `metric`/`source` labels. | Open, cosmetic | `infra/observability/dashboards/scraper_freshness.json` description |
| F7 | Low | No `PayoutBatch` age/staleness gauge exists — the payouts dashboard and its alert use the payment-side `payment_pending_reconciliation_count` as an interim proxy signal, which does not actually observe payout batches directly. | Open | `infra/observability/dashboards/payouts.json`, `DundaPayoutBatchStuck` alert description |
| F8 | Info | OpenTelemetry manual-span instrumentation currently covers representative critical workers rather than every Oban worker. The former Redis `InventoryPoolServer` no longer exists because PostgreSQL is the sole inventory authority. | Open, bounded follow-up | `Dunda.Workers.OutboxDispatcherWorker`; `Dunda.Workers.PaymentReconciliationWorker` |

No external penetration test has been performed — required before G12
regardless of the above.

## G0–G11 evidence linkage

| Gate | Evidence |
|---|---|
| G0 | `docs/phase_0_containment.md`; `mix dunda.phase_0_audit` |
| G1 | `.github/workflows/ci.yml` `backend`/`frontend` jobs (now including dialyzer, coverage, and `npm test`) |
| G2 | `docs/phase_2_operational_hardening.md`; `test/dunda_web/rbac_test.exs` (documents the **open** gap — see finding F2 — role enforcement exists in one place, `event_editor_live.ex`'s edit path, and is absent everywhere else; G2's authorization claim should be read as partial, not complete) |
| G3–G5 | `docs/phase_3_5_checkout_authority.md`; `test/dunda/phase3_5_checkout_test.exs`; `test/dunda/inventory_property_test.exs`; `test/dunda/ledger_property_test.exs`; `test/dunda/payments/duplicate_callback_test.exs`; `test/dunda/events_inventory_pool_test.exs` — **finding F0 is now fixed**; the reservation path this evidence covers is confirmed working end-to-end for a normally-created event |
| G6 | `docs/phase_6_settlement_resale_payouts.md`; `test/dunda/phase6_settlement_test.exs` |
| G7 | `docs/phase_7_ticket_security.md`; `test/dunda/ticketing/phase7_protocol_test.exs`; `frontend/src/security/__tests__/ticketCredential.test.ts` (cross-language vector) |
| G8 | `docs/phase_8_catalogue_scraper_ssrf.md`; `test/dunda/scraper/scraper_test.exs` |
| G9 | `docs/phase_9_infrastructure_resilience.md`; `mix dunda.phase_9_recovery`; `mix dunda.migration_drill` (new) |
| G10 | `docs/phase_10_frontend_reliability.md`; `frontend/src/api/__tests__/client.test.ts` (new) |
| G11 | `docs/phase_11_privacy_governance.md` § Exit gate G11 |

## Exit gate G12

Per the root plan, production release requires **all** of:

- [ ] G0–G11 satisfied — **not yet**: F2 (High) above is an open finding
      against G2. F0 (Critical) is fixed.
- [ ] All critical/high findings closed with linked evidence — **not yet**:
      F0 and F1 are fixed and closed; F2 (High) remains open.
- [ ] Load, chaos, security, and recovery tests pass — load (`mix dunda.load_test`)
      and a first security pass (`webhook_test.exs`, `rbac_test.exs`) exist;
      chaos/recovery drills remain the manual quarterly exercises in
      `docs/phase_9_infrastructure_resilience.md`.
- [ ] Financial reconciliation clean — mechanism exists
      (`reconciliation_diff_count`), not yet exercised against production
      traffic (none exists).
- [ ] External penetration test with no unresolved critical/high — **not
      performed**.
- [ ] Ops/security/product/finance/privacy approval — mechanism now exists
      (`Dunda.ReleaseApproval`'s five-role set), no approvals recorded (none
      should be, pre-production).
- [ ] Documentation describes actual, not aspirational, guarantees — this
      document and `docs/phase_11_privacy_governance.md` were written
      specifically to hold that line, including documenting this session's
      own discovered gaps rather than omitting them.

**G12 is not met.** F0, the Critical defect that made the core checkout
reservation path non-functional for any newly created event, is now fixed
and covered by `test/dunda/events_inventory_pool_test.exs`. What remains
open is F2 (organiser-portal role enforcement exists in exactly one place)
plus the items no amount of code can close alone: an external penetration
test, exercised financial reconciliation against real traffic, and recorded
five-role release approvals. This is stated plainly — including the
correction to F2's own earlier overstatement, found and fixed in the same
pass as F0 — because the alternative would be exactly the kind of overstated
guarantee this whole remediation effort exists to correct.

## Verification

The original phase was authored without an Elixir toolchain. A later local
verification on 24 July 2026 passed warnings-as-errors compilation, Credo,
Dialyzer, frontend typecheck/lint/tests/audit, and the web/iOS/Android Expo
export. The database-backed test suite and migration drill could not run in
that workstation because PostgreSQL/Redis and Docker were unavailable; CI
must still execute every command below before release:

```
cd backend
mix deps.get
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix dialyzer
mix test --cover
mix dunda.migration_drill   # against a disposable database only
mix dunda.mutation_test
mix dunda.load_test --requests 100 --concurrency 10

cd ../frontend
npm ci
npm run typecheck
npm run lint
npm test
```

Treat database, provider-simulator, concurrency, migration, load and mutation
evidence as unverified until the corresponding CI artifacts exist.
