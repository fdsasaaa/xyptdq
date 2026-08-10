# File-queue publisher runtime

## Why this exists

The production PHP 7.4 environment currently lacks `pdo_sqlite`. Installing a new PHP extension only to hold a small article schedule adds operational risk and is unnecessary.

The preferred runtime therefore uses:

- GitHub `content/scheduled/*.json` as the versioned article inventory;
- `/var/lib/xyptdq-publisher/state.json` as server-only runtime state;
- `flock` as the single-process lock;
- the CMS database itself plus a durable publish mapping in the future CMS adapter for crash-safe idempotency.

No SQLite extension is required.

## Current safety state

`auto_publish_filequeue.php` is usable now in **dry-run** mode. Production writes remain deliberately blocked until both conditions are true:

1. `config/publisher_capabilities.json` has `verified: true`;
2. it also has `durable_idempotency_verified: true` and `scripts/content/cms_publish_adapter.php` exists.

The WorkBuddy summary marked `Publisher probe: PASS`, but the submitted evidence only names the three tables `dr_1_news`, `dr_1_news_data_0`, and `dr_1_share_category`. That is not enough to infer the write semantics of `dr_1_news_hits`, `dr_1_news_index`, `dr_1_news_time`, and `dr_1_news_search`. The write lock must remain in place.

## Runtime layout

```text
/opt/xyptdq-repo/                  # read-only Git working copy
  content/scheduled/               # versioned article JSON files
  scripts/content/auto_publish_filequeue.php

/var/lib/xyptdq-publisher/
  state.json                       # not in Git
  publisher.lock                   # not in Git
```

## Dry-run

```bash
cd /opt/xyptdq-repo
php scripts/content/auto_publish_filequeue.php --limit=2
```

This scans all scheduled JSON files, validates them, reports due items, and performs no CMS write.

## Commit mode

Commit mode is intentionally unavailable until the CMS adapter is verified:

```bash
php scripts/content/auto_publish_filequeue.php --commit --limit=2
```

If capability/idempotency gates are not verified, the process exits without writing to the CMS.

## Crash model

Local `state.json` alone cannot prevent a duplicate if the process dies after the CMS transaction commits but before the state file is updated. Therefore the future CMS adapter must implement durable idempotency in MariaDB, preferably through an isolated mapping table keyed by `article_key`, and perform the mapping insert and CMS article writes in the same transaction.

## Production cadence after adapter verification

A low-frequency cron is sufficient, for example every 15 minutes. The publisher itself uses each article's `publish_at`, so the cron cadence does not determine the editorial schedule.

A separate, read-only `git pull --ff-only` job can update `/opt/xyptdq-repo` before publisher execution. If the repository becomes private, use a read-only Deploy Key; never place a PAT in a remote URL.
