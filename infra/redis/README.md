# Redis operating profile

The production application configures `INVENTORY_AUTHORITY=postgres` and uses
Redis only for disposable projections, rate limiting, OTP/session state, and
short-lived acceleration. Redis loss must not destroy tickets, payments,
reservations, or ledger facts; `Dunda.Checkout.reconcile_redis_projection/0`
rebuilds inventory projections from PostgreSQL.

Use a managed primary/replica or Sentinel service with authentication, TLS,
memory limits, eviction alerts, encrypted backups according to the data class,
and network policy restricting API-worker egress. The committed
`redis.conf` is a non-production projection profile and is not a substitute
for managed Redis ACL/TLS configuration.

`INVENTORY_AUTHORITY=redis_legacy` is test/containment-only and must never be
enabled by a production release approval. The old cross-pool Lua escrow path
is not compatible with Redis Cluster; do not place it behind a cluster endpoint.
