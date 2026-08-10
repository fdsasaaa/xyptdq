#!/bin/bash
# One-time activation of the verified native-Xunrui scheduled publisher.
# Performs only a dry-run of the empty scheduled queue before installing cron.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
CRON_FILE="/etc/cron.d/xyptdq-publisher"
PHASE="init"
DRY_RUN="NO"
CRON="NO"
CRON_DAEMON="UNKNOWN"
QUEUE_JSON_COUNT=-1
NATIVE_ADAPTER="NO"
CAPABILITY="NO"

[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3

write_payload() {
  local status="$1" blocker="$2"
  python3 - "$RESULT_FILE" "$status" "$blocker" "$PHASE" "$DRY_RUN" "$CRON" "$CRON_DAEMON" "$QUEUE_JSON_COUNT" "$NATIVE_ADAPTER" "$CAPABILITY" <<'PY'
import json,sys
(out,status,blocker,phase,dry,cron,daemon,count,adapter,cap)=sys.argv[1:]
payload={
 'task':'activate_native_publisher_cron',
 'activation_status':status,
 'phase':phase,
 'blocking_item':blocker,
 'capability_unlock':cap,
 'native_adapter':adapter,
 'scheduled_queue_json_count':int(count),
 'scheduler_dry_run':dry,
 'publisher_cron':cron,
 'cron_daemon':daemon,
 'secrets_disclosed':False,
}
with open(out,'w',encoding='utf-8') as fh:
 json.dump(payload,fh,ensure_ascii=False,indent=2,sort_keys=True); fh.write('\n')
PY
}
block(){ write_payload BLOCKED "$1"; echo "[publisher-activate] BLOCKED: $1" >&2; exit 1; }

cd "$REPO"
PHASE="repo_sync"
[ -z "$(git status --porcelain)" ] || block production_repo_dirty
git fetch --prune origin
git checkout main >/dev/null 2>&1
git reset --hard origin/main >/dev/null

PHASE="capability"
[ -s config/publisher_capabilities.json ] || block capability_manifest_missing
CAP=$(php -r '$x=json_decode(file_get_contents($argv[1]),true); echo (($x["verified"]??false)===true && ($x["durable_idempotency_verified"]??false)===true && ($x["adapter"]??"")==="scripts/content/cms_publish_native_adapter.php")?"1":"0";' config/publisher_capabilities.json)
[ "$CAP" = 1 ] || block capability_not_unlocked_for_native_adapter
CAPABILITY="PASS"

PHASE="adapter"
[ -s scripts/content/cms_publish_native_adapter.php ] || block native_adapter_missing
[ -s scripts/content/run_scheduled_publish.sh ] || block scheduler_missing
[ -s scripts/content/install_publisher_cron.sh ] || block cron_installer_missing
php -l scripts/content/cms_publish_native_adapter.php >/dev/null
bash -n scripts/content/run_scheduled_publish.sh
bash -n scripts/content/install_publisher_cron.sh
grep -Fq 'cms_publish_native_adapter.php' scripts/content/run_scheduled_publish.sh || block scheduler_not_pinned_to_native_adapter
NATIVE_ADAPTER="PASS"

PHASE="empty_queue"
[ -d content/scheduled ] || block scheduled_queue_missing
QUEUE_JSON_COUNT=$(find content/scheduled -maxdepth 1 -type f -name '*.json' | wc -l | tr -d ' ')
[ "$QUEUE_JSON_COUNT" -eq 0 ] || block scheduled_queue_not_empty_at_activation

PHASE="dry_run"
TMP_STATE=$(mktemp /tmp/xyptdq-publisher-activation-state.XXXXXX.json)
TMP_LOCK=$(mktemp /tmp/xyptdq-publisher-activation-lock.XXXXXX)
rm -f "$TMP_STATE" "$TMP_LOCK"
OUT=$(mktemp /tmp/xyptdq-publisher-activation.XXXXXX.log)
cleanup(){ rm -f "$TMP_STATE" "$TMP_LOCK" "$OUT"; }
trap cleanup EXIT
php scripts/content/auto_publish_filequeue.php \
  --source="$REPO/content/scheduled" \
  --state="$TMP_STATE" \
  --lock="$TMP_LOCK" \
  --limit=2 \
  --adapter="$REPO/scripts/content/cms_publish_native_adapter.php" >"$OUT" 2>&1 || block scheduler_dry_run_failed
grep -Fq 'source=0 due=0' "$OUT" || block scheduler_dry_run_not_empty
grep -Fq 'mode=DRY-RUN' "$OUT" || block scheduler_dry_run_marker_missing
DRY_RUN="PASS"

PHASE="cron_install"
bash scripts/content/install_publisher_cron.sh >/dev/null
[ -s "$CRON_FILE" ] || block cron_file_missing
[ "$(stat -c '%U:%G:%a' "$CRON_FILE")" = 'root:root:644' ] || block cron_file_permissions_invalid
grep -Fq '7 * * * * root XYPTDQ_REPO_DIR=/opt/xyptdq-repo /opt/xyptdq-repo/scripts/content/run_scheduled_publish.sh' "$CRON_FILE" || block cron_entry_invalid
CRON="PASS"

PHASE="cron_daemon"
if systemctl is-active --quiet cron 2>/dev/null; then
  CRON_DAEMON="cron:active"
elif systemctl is-active --quiet crond 2>/dev/null; then
  CRON_DAEMON="crond:active"
else
  block cron_daemon_inactive
fi

PHASE="final"
write_payload PASS NONE
echo PUBLISHER_NATIVE_CRON_ACTIVATION=PASS
