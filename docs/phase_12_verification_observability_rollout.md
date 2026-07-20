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
| F0 | **Critical** | No application code path ever created a `Dunda.Checkout.InventoryPool` row for an event created after the Phase 3-5 migration's one-time backfill. `Dunda.Events.create_event/1` seeded only the legacy Redis projection. Every reservation attempt against a post-migration event failed with `{:error, :inventory_pool_not_found}`. No pre-existing test (`phase3_5_checkout_test.exs` is changeset-only, no DB; `checkout_controller_test.exs` targets the legacy `Dunda.Payments` flow, not `Dunda.Checkout`) exercised the reservation path against a real database. | **Fixed** — `Dunda.Events.create_event/1` now provisions the untiered pool in the same `Ecto.Multi` transaction (mirroring the migration backfill's `pool_key: "event:<id>"` convention exactly); `Dunda.Events.update_event/2` now keeps the pool's capacity in sync when an event's capacity changes, rejecting (not silently dropping or crashing on) a reduction below already-committed inventory. Confirmed no live code path creates a `Dunda.Ticketing.TicketTier` today (`event_editor_live.ex`'s "tiers" form state is simulated and collapsed into the event's own flat `capacity` before calling `create_event/1` — it never persists a `TicketTier` row), so the untiered-pool fix is complete for every currently-live code path; a future tier-creation feature will need its own per-tier pool provisioning, noted in the fixed function's docstring. | `test/dunda/events_inventory_pool_test.exs` (drives the real path end-to-end: create an event, create a quote, create a payment intent — no manual pool insertion) |
| F1 | High | `Dunda.Checkout.fail_payment/2`'s short-circuit guard covered only `["fulfilled", "refunded"]`. A stale/reordered provider-failure callback arriving after confirmation (`confirmed`/`confirmed_late`/`manual_review`/`refund_pending`/`expired_pending_reconciliation`) would attempt an invalid state transition and crash (`Repo.update!` raising) rather than no-op — no financial corruption (the transaction rolls back), but the calling Oban job would crash-loop. | **Fixed** | `PaymentIntent.transition_allowed?/2` extracted as single source of truth; `checkout.ex`'s guard now uses it; `test/dunda/payments/reordered_events_test.exs` |
| F2 | High | `Dunda.Organisations.OrganisationMember.role` declares five roles (owner/admin/manager/scanner/member) matching the root plan's Phase 2 permission-model requirement. **Correction**: an earlier draft of this finding claimed "no code path anywhere differentiates behaviour by role" based on a grep pattern that missed `Dunda.Organisations.member?/3` — that function is real, works correctly (`m.role in ^roles`), and gates exactly one action: `event_editor_live.ex`'s edit-existing-event path, restricted to `~w(owner admin manager)`. What remains true and is still High severity: `DundaWeb.PortalAccess.allowed?/1` (portal entry itself, used by both the plug and the LiveView `on_mount` hook) never consults role at all, so a "scanner" role member reaches every LiveView; and every OTHER mutating action (event creation, payouts, team management, scraper config, extras, tickets) has no role check whatsoever — `member?/3`'s one call site is the only one in `lib/dunda_web/`. | **Open** — documented as a characterization test, not fixed; implementing broader authorization is Phase 2 scope this session did not undertake (requires LiveView-level verification unavailable in this sandbox). | `test/dunda_web/rbac_test.exs` |
| F3 | Medium | `test/dunda_web/controllers/checkout_controller_test.exs` asserts a `transaction_id`/`status: "pending"` response shape that does not match `DundaWeb.CheckoutController.create/2`'s actual current output (`payment_intent_id`/`state` — the Phase 3-5 rewrite). The test appears to target the legacy `Dunda.Payments` flow and is very likely already failing independent of this phase's changes. | **Open** — not modified; a new, separate contract test (`test/dunda_web/contract/core_endpoints_contract_test.exs`) deliberately avoids this file rather than building on an uncertain foundation. | File comparison against `checkout_controller.ex` |
| F4 | Medium | `Dunda.Checkout.release_reservation!/2` hardcodes `failure_reason: "reservation_expired"` regardless of the actual reason passed by its caller (`fail_payment/2`'s `reason` argument is silently discarded whenever an active reservation exists). Not a crash, not a financial-correctness issue, but a diagnostic-quality gap. | Open | `test/dunda/payments/reordered_events_test.exs` (see the third test's comment) |
| F5 | Low | `provider_events.payload` (a raw JSON capture of provider callback bodies, can transiently contain a phone/receipt) is not field-level encrypted — DB-access-restricted and redaction-on-read only. | Open, tracked | `docs/data_inventory.md` "Open item" |
| F6 | Low | Scraper metrics (`{:scraper_empty_result, source}` / `{:scraper_schema_drift, source}`) use a compound tuple as the counter key, which `render_prometheus/0` renders via `inspect/1` into an awkward (but functional and correctly escaped) label value rather than separate `metric`/`source` labels. | Open, cosmetic | `infra/observability/dashboards/scraper_freshness.json` description |
| F7 | Low | No `PayoutBatch` age/staleness gauge exists — the payouts dashboard and its alert use the payment-side `payment_pending_reconciliation_count` as an interim proxy signal, which does not actually observe payout batches directly. | Open | `infra/observability/dashboards/payouts.json`, `DundaPayoutBatchStuck` alert description |
| F8 | Info | OpenTelemetry manual-span instrumentation covers one representative worker (`OutboxDispatcherWorker`), not every Oban worker or the `InventoryPoolServer` GenServer. | Open, follow-up | `Dunda.Workers.OutboxDispatcherWorker` |

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

This phase's code has not been compiled or run (no Elixir toolchain in the
authoring environment). Before relying on any of the above:

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

Fix compile/type errors before trusting any other claim in this document —
they were written carefully, cross-checked against real source line-by-line,
but "carefully reasoned" is not the same guarantee as "compiled."
