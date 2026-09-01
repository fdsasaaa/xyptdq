# Scheduled queue reconciliation (2026-09-01)

The 11 `seo-ffc-*` JSON files in this directory belong to the retired
`seo-articles` category era. They are preserved here as immutable audit
history. The publisher does NOT consume this directory
(`legacy_repository_queue_consumed=false`), and per the bridge contract the
legacy queue must not be migrated into the runtime scheduling path.

Current runtime scheduling uses isolated queues under
`/var/lib/xyptdq-content/DAILY-20260901/scheduled` (see
`docs/ops/FRESH_RUNTIME_RECONCILIATION_20260901.md`).
