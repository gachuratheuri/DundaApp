# Backup and reconstruction runbook

## PostgreSQL

Use the managed PostgreSQL service's encrypted snapshot and point-in-time
recovery facilities. WAL is archived to a separate, access-controlled storage
account with customer-managed encryption keys where available. Application
secrets and database encryption keys are never stored in this repository.

The backup monitor must record:

- last successful snapshot and WAL archive timestamps;
- backup object checksum/size and retention expiry;
- restore-test duration and resulting PostgreSQL version;
- RPO/RTO measured by the latest isolated restore.

To verify a backup, restore it into an isolated instance (never the live
primary), run migrations, and execute the financial/inventory reconciliation
queries from `docs/phase_5_post_release_assurance.md`. Capture the output as
release evidence and destroy the isolated instance according to the retention
policy.

Additionally, before the drill (or before a backup's retention window expires
and it is deleted), capture a protected-row-count baseline and verify it
after — this turns "quarterly restoration drills must demonstrate no
statutory record loss" from a manual eyeball check into an automatable,
exit-code-driven one (`backend/test/dunda/retention_test.exs` covers the same
invariant at the application level; this covers it at the infrastructure
backup/restore level):

```text
mix dunda.backup_retention_check --capture-baseline /tmp/baseline.json
# ... perform the restore drill ...
mix dunda.backup_retention_check --verify /tmp/baseline.json
```

## Redis reconstruction

Redis is disposable in production. After a Redis failover or data loss:

1. provision/authenticate the managed Redis endpoint with TLS;
2. keep checkout writes enabled only if PostgreSQL is healthy;
3. run `mix dunda.phase_9_recovery --rebuild-redis` from a supervised release
   task (it delegates to `Dunda.Checkout.reconcile_redis_projection/0`);
4. verify the reported mismatch count is zero and compare a sample of hot tiers
   with PostgreSQL;
5. re-enable cache-dependent acceleration after the reconciliation metric is
   green.

Do not copy an RDB/AOF snapshot into a different topology as a substitute for
   reconstruction; `INVENTORY_AUTHORITY` must remain `postgres` in every
   production deployment.

## Access and retention

Backups are encrypted in transit and at rest, access is least-privilege and
audited, and retention is documented per data class. Restore credentials are
short-lived. Quarterly restoration drills must demonstrate that deleting or
expiring a backup does not delete the PostgreSQL records required for statutory
financial retention.
