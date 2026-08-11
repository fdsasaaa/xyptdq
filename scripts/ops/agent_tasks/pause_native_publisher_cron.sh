#!/bin/bash
# Pause the verified scheduled publisher cron without touching queued articles
# or the native Publisher implementation. Re-enable later with install_publisher_cron.sh.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
CRON_FILE="/etc/cron.d/xyptdq-publisher"
EXPECTED='7 * * * * root XYPTDQ_REPO_DIR=/opt/xyptdq-repo /opt/xyptdq-repo/scripts/content/run_scheduled_publish.sh'

PHASE="init"
STATUS="UNKNOWN"
QUEUE_COUNT=-1
CRON_BEFORE="UNKNOWN"
CRON_AFTER="UNKNOWN"
OTHER_REFS=-1

[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3

write_payload() {
  local result_status="$1" blocker="$2"
  python3 - "$RESULT_FILE" "$result_status" "$blocker" "$PHASE" "$STATUS" "$QUEUE_COUNT" "$CRON_BEFORE" "$CRON_AFTER" "$OTHER_REFS" <<'PY'
import json,sys
(out,result_status,blocker,phase,pause_status,queue_count,before,after,other_refs)=sys.argv[1:]
payload={
  "task":"pause_native_publisher_cron",
  "pause_status":pause_status,
  "phase":phase,
  "blocking_item":blocker,
  "scheduled_queue_json_count":int(queue_count),
  "cron_before":before,
  "cron_after":after,
  "other_active_publisher_cron_refs":int(other_refs),
  "queued_articles_deleted":False,
  "publisher_code_changed":False,
  "article_publishing_attempted":False,
  "secrets_disclosed":False,
}
with open(out,"w",encoding="utf-8") as f:
    json.dump(payload,f,ensure_ascii=False,indent=2,sort_keys=True)
    f.write("\n")
PY
}
block(){ STATUS="BLOCKED"; write_payload FAIL "$1"; echo "[publisher-pause] BLOCKED: $1" >&2; exit 1; }

cd "$REPO"
PHASE="repo_sync"
[ -z "$(git status --porcelain)" ] || block production_repo_dirty
git fetch --prune origin >/dev/null 2>&1
git checkout main >/dev/null 2>&1
git reset --hard origin/main >/dev/null 2>&1

PHASE="queue_inventory"
if [ -d content/scheduled ]; then
  QUEUE_COUNT=$(find content/scheduled -maxdepth 1 -type f -name '*.json' | wc -l | tr -d ' ')
else
  QUEUE_COUNT=0
fi

PHASE="cron_preflight"
if [ -e "$CRON_FILE" ]; then
  CRON_BEFORE="PRESENT"
  [ -f "$CRON_FILE" ] || block publisher_cron_not_regular_file
  # Only remove the exact cron entry installed by this repository.
  ACTIVE_LINES=$(grep -Ev '^[[:space:]]*(#|$)' "$CRON_FILE" || true)
  [ "$ACTIVE_LINES" = "$EXPECTED" ] || block publisher_cron_content_unexpected
  OWNER_MODE=$(stat -c '%U:%G:%a' "$CRON_FILE")
  case "$OWNER_MODE" in
    root:root:644|root:root:640|root:root:600) ;;
    *) block publisher_cron_owner_mode_unexpected ;;
  esac
else
  CRON_BEFORE="ABSENT"
fi

PHASE="pause"
if [ -e "$CRON_FILE" ]; then
  rm -f -- "$CRON_FILE"
fi
[ ! -e "$CRON_FILE" ] || block publisher_cron_remove_failed
CRON_AFTER="ABSENT"

PHASE="duplicate_guard"
OTHER_REFS=0
while IFS= read -r f; do
  [ "$f" = "$CRON_FILE" ] && continue
  if grep -Fq '/opt/xyptdq-repo/scripts/content/run_scheduled_publish.sh' "$f" 2>/dev/null; then
    OTHER_REFS=$((OTHER_REFS+1))
  fi
done < <(find /etc/cron.d -maxdepth 1 -type f -print 2>/dev/null || true)

ROOT_CRON=$(crontab -u root -l 2>/dev/null || true)
if printf '%s\n' "$ROOT_CRON" | grep -Fq '/opt/xyptdq-repo/scripts/content/run_scheduled_publish.sh'; then
  OTHER_REFS=$((OTHER_REFS+1))
fi
[ "$OTHER_REFS" -eq 0 ] || block alternate_publisher_cron_reference_detected

PHASE="final"
STATUS="PASS"
write_payload PASS NONE
echo "PUBLISHER_NATIVE_CRON_PAUSE=PASS queue_json_count=$QUEUE_COUNT"
