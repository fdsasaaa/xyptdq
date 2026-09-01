#!/bin/bash
# Install the durable ordinary-SEO promotion cron (Phase 5) and re-point the
# publisher cron source to the stable ordinary-seo queue (ONE time).
# Weekly cadence: Tuesday / Thursday / Saturday 10:05 SGT.
# Max 3 per calendar week is enforced by promote_ordinary_seo_v1.sh itself.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
POLICY="$REPO/config/content_publication_policy.json"
STABLE_QUEUE="/var/lib/xyptdq-content/ordinary-seo/scheduled"
PROMOTION_CRON="${XYPTDQ_PROMOTION_CRON:-/etc/cron.d/xyptdq-promotion}"
PUBLISHER_CRON="${XYPTDQ_PUBLISHER_CRON:-/etc/cron.d/xyptdq-publisher}"
RUNNER="$REPO/scripts/ops/agent_tasks/promote_ordinary_seo_v1.sh"

PHASE="init"
STATUS="BLOCKED"
BLOCKING_ITEM="NONE"

[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3

write_result(){ python3 - "$RESULT_FILE" "$STATUS" "$PHASE" "$BLOCKING_ITEM" <<'PY'
import json, sys
out, status, phase, blocker = sys.argv[1:]
p = {
  "task": "install_ordinary_seo_promotion_cron_v1",
  "status": status,
  "phase": phase,
  "blocking_item": blocker,
  "cms_write": False,
  "schedule_write": True,
  "cron_write": True,
  "publisher_invoked": False,
}
with open(out, "w", encoding="utf-8") as f:
    json.dump(p, f, ensure_ascii=False, indent=2, sort_keys=True); f.write("\n")
PY
}

block(){ BLOCKING_ITEM="$1"; STATUS="BLOCKED"; write_result; echo "[ordinary-seo-cron] BLOCKED: $1" >&2; exit 1; }

PHASE="sync_main"
cd "$REPO"
# Tolerant sync: the canonical repo may hold transient uncommitted state from the
# result transport; agent jobs never modify the repo, so reset to origin/main is safe.
git fetch --prune origin >/dev/null 2>&1 || true
git checkout -q main 2>/dev/null || git checkout -q -B main origin/main
git reset --hard origin/main >/dev/null

PHASE="preflight"
[ -f "$POLICY" ] || block publication_policy_missing
[ -f "$RUNNER" ] || block promotion_runner_missing
AUTH=$(php -r '$x=json_decode(file_get_contents($argv[1]),true); echo ((($x["ordinary_seo_promotion"]["enabled"]??null)===true)?"yes":"no");' "$POLICY")
[ "$AUTH" = yes ] || block ordinary_seo_promotion_not_enabled_in_policy

PHASE="promotion_cron_install"
install -d -o root -g www-data -m 0750 "$(dirname "$STABLE_QUEUE")" "$STABLE_QUEUE"
TMP=$(mktemp /tmp/xyptdq-promotion-cron.XXXXXX)
trap 'rm -f "$TMP"' EXIT
cat > "$TMP" <<EOF
# Managed by xyptdq. Ordinary SEO promotion: Tue/Thu/Sat 10:05 SGT. Weekly max enforced in runner.
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
5 10 * * 2,4,6 root /bin/bash $RUNNER >/dev/null 2>&1
EOF
chmod 0644 "$TMP"
install -o root -g root -m 0644 "$TMP" "$PROMOTION_CRON"
COUNT=$(grep -R -h -F 'promote_ordinary_seo_v1.sh' /etc/cron.d /etc/crontab 2>/dev/null | grep -v '^#' | wc -l | tr -d ' ')
[ "$COUNT" = 1 ] || block promotion_cron_not_singleton
grep -Fq '5 10 * * 2,4,6 root /bin/bash' "$PROMOTION_CRON" || block promotion_cron_line_mismatch

PHASE="publisher_source_repin"
if [ -f "$PUBLISHER_CRON" ]; then
  if grep -q "XYPTDQ_PUBLISH_SOURCE=$STABLE_QUEUE" "$PUBLISHER_CRON"; then
    :
  else
    sed -i "s|XYPTDQ_PUBLISH_SOURCE=[^ ]*|XYPTDQ_PUBLISH_SOURCE=$STABLE_QUEUE|" "$PUBLISHER_CRON" || block publisher_cron_patch_failed
    grep -q "XYPTDQ_PUBLISH_SOURCE=$STABLE_QUEUE" "$PUBLISHER_CRON" || block publisher_cron_patch_not_verified
  fi
else
  block publisher_cron_missing_cannot_repin_source
fi

PHASE="complete"
STATUS="PASS"
write_result
echo "INSTALL_ORDINARY_SEO_PROMOTION_CRON_V1=PASS stable_queue=$STABLE_QUEUE"
