# Phase 8 — scraper, catalogue, and SSRF controls

## Data authority and provenance

PostgreSQL is authoritative for the event catalogue. The process-local Bloom
filter is only an advisory observation/cache; every normalised row reaches the
database `ON CONFLICT` upsert. This makes Bloom false positives harmless and
ensures changed source fields are written on repeated runs.

Scraped events retain `source`, `external_id`, `source_url`,
`source_last_seen_at`, and a deterministic SHA-256 payload hash. Each ingest
run records source, tenant, counts, status, schema-drift state, response hash,
and timestamps in `scrape_source_runs`.

## SSRF policy

Organiser-controlled HTML targets must use HTTPS, port 443 (or the default),
no userinfo, and an optional configured host allow-list. DNS is resolved for
both IPv4 and IPv6; loopback, private, link-local, multicast, unspecified, and
metadata addresses are rejected. Redirects are disabled in the HTTP client and
manually followed at most three times, with the target revalidated on every
hop. Response size and request time are bounded.

This validation is defence in depth; production must additionally place the
scraper in an egress-isolated network with provider DNS/IP policy enforcement
so a DNS answer cannot be rebound between validation and socket connection.

Provider response envelopes are schema-guarded. Missing event collections are
classified as schema drift rather than silently treated as an empty catalogue.
Empty successful runs are logged for freshness/zero-result alerting.

## Catalogue lifecycle

Public discovery returns only `published` events in the bounded upcoming date
window, with deterministic `(starts_at, id)` ordering, opaque cursors, bounded
page size, and category/city filters. Draft, cancelled, completed, and
cross-tenant records are not exposed through public reads. Organiser reads use
the primary database for read-after-write consistency; public discovery may use
the read replica. Readiness reports replica lag separately.

## Required evidence before G8

- Run the migration against a production-shaped PostgreSQL snapshot.
- Force Bloom false positives and prove that rows still reach the upsert.
- Exercise redirect-to-private-IP, DNS failure/rebinding, IPv4/IPv6 private
  ranges, oversized responses, and timeout cases.
- Run parser fixtures for every supported source and verify schema-drift alerts.
- Verify public pagination cannot reveal drafts, cancelled events, or another
  organisation's records.
- Demonstrate Redis reconstruction and replica-lag behaviour independently.
