# Scheduled article queue

This directory contains versioned article JSON files for the production scheduler.

The directory is intentionally empty at publisher activation time. Production cron may be enabled only after `config/publisher_capabilities.json` records durable native-Xunrui idempotency verification. Each future JSON article must have a unique immutable `article_key`, a reviewed category, and an explicit `publish_at` timestamp.

Do not place test/smoke fixtures here. Smoke fixtures remain under `content/smoke/`.
