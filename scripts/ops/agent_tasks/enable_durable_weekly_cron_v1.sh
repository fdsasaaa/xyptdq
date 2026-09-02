#!/bin/bash
# Re-enable the durable ordinary-SEO weekly promotion cron AFTER E2E canary PASS.
# Server timezone is Etc/UTC (verified by fresh_server_safety_probe_v1) -> CRON_TZ is required
# to pin the schedule to Asia/Singapore. Verifies publisher ordinary-seo isolation is intact.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
PUBLISHER_CRON="${XYPTDQ_PUBLISHER_CRON:-/etc/cron.d/xyptdq-publisher}"
PROMOTION_CRON="${XYPTDQ_PROMOTION_CRON:-/etc/cron.d/xyptdq-promotion}"
PROMOTION_HELD="${PROMOTION_CRON}.held-e2e-20260902"
RUNNER="$REPO/scripts/ops/agent_tasks/promote_ordinary_seo_v1.sh"
STABLE_QUEUE="/var/lib/xyptdq-content/ordinary-seo/scheduled"
ORDINARY_STATE="/var/lib/xyptdq-publisher/ordinary-seo/state.json"
ORDINARY_LOCK="/var/lib/xyptdq-publisher/ordinary-seo/publisher.lock"

PHASE="init"
STATUS="BLOCKED"
BLOCKING_ITEM="NONE"

[ -n "$RESULT_FILE" ] || exit 2

write_result(){ python3 - "$RESULT_FILE" "$STATUS" "$PHASE" "$BLOCKING_ITEM" <<'PY'
import json, sys
out, status, phase, blocker = sys.argv[1:]
p = {
  "task": "enable_durable_weekly_cron_v1",
  "status": status,
  "phase": phase,
  "blocking_item": blocker,
  "cms_write": False,
  "publisher_invoked": False,
}
with open(out, "w", encoding="utf-8") as f:
    json.dump(p, f, ensure_ascii=False, indent=2, sort_keys=True); f.write("\n")
PY
}

block(){ BLOCKING_ITEM="$1"; STATUS="BLOCKED"; write_result; echo "[enable-weekly-cron] BLOCKED: $1" >&2; exit 1; }

PHASE="preflight"
[ -f "$RUNNER" ] || block promotion_runner_missing
[ -f "$PUBLISHER_CRON" ] || block publisher_cron_missing

PHASE="publisher_isolation_verify"
grep -q "XYPTDQ_PUBLISH_SOURCE=$STABLE_QUEUE" "$PUBLISHER_CRON" || block publisher_source_not_ordinary_seo
grep -q "XYPTDQ_PUBLISH_STATE=$ORDINARY_STATE" "$PUBLISHER_CRON" || block publisher_state_not_ordinary_seo
grep -q "XYPTDQ_PUBLISH_LOCK=$ORDINARY_LOCK" "$PUBLISHER_CRON" || block publisher_lock_not_ordinary_seo

PHASE="restore_promotion_cron"
# restore from held backup if present, else write fresh
if [ -f "$PROMOTION_HELD" ]; then
  mv "$PROMOTION_HELD" "$PROMOTION_CRON"
else
  TMP=$(mktemp /tmp/xyptdq-promotion.XXXXXX)
  trap 'rm -f "$TMP"' EXIT
  cat > "$TMP" <<EOF
# Managed by xyptdq. Ordinary SEO promotion: Tue/Thu/Sat 10:05 Asia/Singapore (CRON_TZ).
# Server system timezone is Etc/UTC; CRON_TZ pins the schedule to Asia/Singapore.
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
CRON_TZ=Asia/Singapore
5 10 * * 2,4,6 root /bin/bash $RUNNER >/dev/null 2>&1
EOF
  chmod 0644 "$TMP"
  install -o root -g root -m 0644 "$TMP" "$PROMOTION_CRON"
fi
grep -Fq 'CRON_TZ=Asia/Singapore' "$PROMOTION_CRON" || block crontz_missing
grep -Fq '5 10 * * 2,4,6 root /bin/bash' "$PROMOTION_CRON" || block promotion_line_missing

PHASE="singleton_verify"
PROMO_COUNT=$(grep -R -h -F 'promote_ordinary_seo_v1.sh' /etc/cron.d /etc/crontab 2>/dev/null | grep -v '^#' | wc -l | tr -d ' ')
[ "$PROMO_COUNT" -eq 1 ] || block promotion_cron_not_singleton
PUB_COUNT=$(grep -R -h -F 'run_scheduled_publish.sh' /etc/cron.d /etc/crontab 2>/dev/null | grep -v '^#' | wc -l | tr -d ' ')
[ "$PUB_COUNT" -eq 1 ] || block publisher_cron_not_singleton

PHASE="complete"
STATUS="PASS"
write_result
echo "ENABLE_DURABLE_WEEKLY_CRON_V1=PASS crontz=Asia/Singapore promotion_singleton=$PROMO_COUNT publisher_singleton=$PUB_COUNT"
