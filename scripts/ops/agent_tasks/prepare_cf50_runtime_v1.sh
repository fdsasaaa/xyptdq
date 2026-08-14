#!/bin/bash
# Prepare empty isolated CF50 Draft/Scheduled and Publisher state directories.
# This task never enables publishing, installs cron, writes article files, or touches CMS data.
set -euo pipefail
umask 027

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
BATCH_ID="CF50-20260813"
QUEUE_ROOT="/var/lib/xyptdq-content"
BATCH_ROOT="$QUEUE_ROOT/$BATCH_ID"
DRAFT_DIR="$BATCH_ROOT/drafts"
SCHEDULED_DIR="$BATCH_ROOT/scheduled"
PUBLISHER_ROOT="/var/lib/xyptdq-publisher"
STATE_DIR="$PUBLISHER_ROOT/$BATCH_ID"
POLICY="$REPO/config/content_publication_policy.json"
LEGACY_QUEUE="$REPO/content/scheduled"
EXPECTED_LEGACY_JSON_COUNT=11

PHASE="init"
STATUS="NO"
ROLLBACK="NO"
POLICY_DISABLED="NO"
CRON_BEFORE=-1
CRON_AFTER=-1
LEGACY_BEFORE=-1
LEGACY_AFTER=-1
DRAFT_COUNT=-1
SCHEDULED_COUNT=-1
STATE_COUNT=-1
PATH_GUARDS="NO"
ERROR_CLASS="NONE"
BLOCKING_ITEM="NONE"
CREATED_BATCH=0
CREATED_DRAFT=0
CREATED_SCHEDULED=0
CREATED_STATE=0

[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3

write_payload(){ python3 - "$RESULT_FILE" "$1" "$PHASE" "$STATUS" "$ROLLBACK" "$POLICY_DISABLED" "$CRON_BEFORE" "$CRON_AFTER" "$LEGACY_BEFORE" "$LEGACY_AFTER" "$DRAFT_COUNT" "$SCHEDULED_COUNT" "$STATE_COUNT" "$PATH_GUARDS" "$ERROR_CLASS" "$BLOCKING_ITEM" <<'PY'
import json,sys
(out,result,phase,status,rollback,policy,cron_before,cron_after,legacy_before,legacy_after,draft_count,scheduled_count,state_count,path_guards,error_class,blocker)=sys.argv[1:]
p={
  "task":"prepare_cf50_runtime_v1",
  "result":result,
  "phase":phase,
  "runtime_status":status,
  "rollback":rollback,
  "publication_policy_disabled":policy,
  "publisher_cron_count_before":int(cron_before),
  "publisher_cron_count_after":int(cron_after),
  "legacy_scheduled_json_count_before":int(legacy_before),
  "legacy_scheduled_json_count_after":int(legacy_after),
  "draft_runtime_file_count":int(draft_count),
  "scheduled_runtime_file_count":int(scheduled_count),
  "publisher_state_runtime_file_count":int(state_count),
  "path_guards":path_guards,
  "queue_root":"/var/lib/xyptdq-content/CF50-20260813",
  "draft_dir":"/var/lib/xyptdq-content/CF50-20260813/drafts",
  "scheduled_dir":"/var/lib/xyptdq-content/CF50-20260813/scheduled",
  "publisher_state_dir":"/var/lib/xyptdq-publisher/CF50-20260813",
  "publisher_state_file":"/var/lib/xyptdq-publisher/CF50-20260813/state.json",
  "publisher_lock_file":"/var/lib/xyptdq-publisher/CF50-20260813/publisher.lock",
  "error_class":error_class,
  "blocking_item":blocker,
  "database_changed":False,
  "article_file_written":False,
  "article_publishing_attempted":False,
  "publisher_policy_changed":False,
  "publisher_cron_changed":False,
  "legacy_queue_consumed":False,
  "secrets_disclosed":False
}
with open(out,'w',encoding='utf-8') as f:
    json.dump(p,f,ensure_ascii=False,indent=2,sort_keys=True); f.write('\n')
PY
}

count_json(){ find "$1" -maxdepth 1 -type f -name '*.json' -printf '.' 2>/dev/null | wc -c; }
count_entries(){ find "$1" -mindepth 1 -maxdepth 1 -printf '.' 2>/dev/null | wc -c; }
cron_count(){ (crontab -l 2>/dev/null || true; cat /etc/cron.d/xyptdq-publisher 2>/dev/null || true) | grep -c 'run_scheduled_publish.sh' || true; }

rollback_created(){
  set +e
  [ "$CREATED_STATE" -eq 1 ] && [ "$(count_entries "$STATE_DIR")" -eq 0 ] && rmdir "$STATE_DIR" 2>/dev/null
  [ "$CREATED_SCHEDULED" -eq 1 ] && [ "$(count_entries "$SCHEDULED_DIR")" -eq 0 ] && rmdir "$SCHEDULED_DIR" 2>/dev/null
  [ "$CREATED_DRAFT" -eq 1 ] && [ "$(count_entries "$DRAFT_DIR")" -eq 0 ] && rmdir "$DRAFT_DIR" 2>/dev/null
  [ "$CREATED_BATCH" -eq 1 ] && [ -d "$BATCH_ROOT" ] && [ "$(count_entries "$BATCH_ROOT")" -eq 0 ] && rmdir "$BATCH_ROOT" 2>/dev/null
  ROLLBACK="YES"
  set -e
}

block(){
  BLOCKING_ITEM="$1"
  rollback_created
  write_payload BLOCKED
  echo "[prepare-cf50-runtime] BLOCKED: $BLOCKING_ITEM class=$ERROR_CLASS" >&2
  exit 1
}

on_err(){
  rc=$?
  trap - ERR
  ERROR_CLASS="unhandled_runtime_error"
  BLOCKING_ITEM="phase_${PHASE}_exit_${rc}"
  rollback_created
  write_payload BLOCKED || true
  exit "$rc"
}
trap on_err ERR

PHASE="repo_sync"
cd "$REPO"
git fetch --prune origin main >/dev/null 2>&1

git merge-base --is-ancestor HEAD origin/main >/dev/null 2>&1 || true
[ -s "$POLICY" ] || { ERROR_CLASS="publication_policy_missing"; block publication_policy_missing; }
[ -d "$LEGACY_QUEUE" ] || { ERROR_CLASS="legacy_queue_missing"; block legacy_queue_missing; }

PHASE="safety_preflight"
POLICY_ENABLED=$(php -r '$x=json_decode(file_get_contents($argv[1]),true); if(!is_array($x)){exit(2);} echo (($x["publishing_enabled"]??null)===true)?"yes":"no";' "$POLICY") || { ERROR_CLASS="publication_policy_invalid"; block publication_policy_invalid; }
[ "$POLICY_ENABLED" = "no" ] || { ERROR_CLASS="publication_policy_unexpectedly_enabled"; block publication_policy_unexpectedly_enabled; }
POLICY_DISABLED="PASS"
CRON_BEFORE="$(cron_count)"
[ "$CRON_BEFORE" -eq 0 ] || { ERROR_CLASS="publisher_cron_present"; block publisher_cron_present; }
LEGACY_BEFORE="$(count_json "$LEGACY_QUEUE")"
[ "$LEGACY_BEFORE" -eq "$EXPECTED_LEGACY_JSON_COUNT" ] || { ERROR_CLASS="legacy_queue_count_drift"; block legacy_queue_count_drift; }

for p in "$BATCH_ROOT" "$DRAFT_DIR" "$SCHEDULED_DIR" "$STATE_DIR"; do
  [ ! -L "$p" ] || { ERROR_CLASS="runtime_path_is_symlink"; block "runtime_path_is_symlink_$p"; }
done

PHASE="prepare"
install -d -o root -g www-data -m 0750 "$QUEUE_ROOT" "$PUBLISHER_ROOT"
if [ ! -d "$BATCH_ROOT" ]; then CREATED_BATCH=1; fi
install -d -o root -g www-data -m 0750 "$BATCH_ROOT"
if [ ! -d "$DRAFT_DIR" ]; then CREATED_DRAFT=1; fi
install -d -o root -g www-data -m 0750 "$DRAFT_DIR"
if [ ! -d "$SCHEDULED_DIR" ]; then CREATED_SCHEDULED=1; fi
install -d -o root -g www-data -m 0750 "$SCHEDULED_DIR"
if [ ! -d "$STATE_DIR" ]; then CREATED_STATE=1; fi
install -d -o root -g www-data -m 0750 "$STATE_DIR"

PHASE="path_verify"
QUEUE_ROOT_REAL=$(realpath "$QUEUE_ROOT")
BATCH_REAL=$(realpath "$BATCH_ROOT")
DRAFT_REAL=$(realpath "$DRAFT_DIR")
SCHEDULED_REAL=$(realpath "$SCHEDULED_DIR")
PUBLISHER_ROOT_REAL=$(realpath "$PUBLISHER_ROOT")
STATE_REAL=$(realpath "$STATE_DIR")
case "$BATCH_REAL/" in "$QUEUE_ROOT_REAL"/*) ;; *) ERROR_CLASS="batch_path_escape"; block batch_path_escape;; esac
case "$DRAFT_REAL/" in "$BATCH_REAL"/*) ;; *) ERROR_CLASS="draft_path_escape"; block draft_path_escape;; esac
case "$SCHEDULED_REAL/" in "$BATCH_REAL"/*) ;; *) ERROR_CLASS="scheduled_path_escape"; block scheduled_path_escape;; esac
case "$STATE_REAL/" in "$PUBLISHER_ROOT_REAL"/*) ;; *) ERROR_CLASS="state_path_escape"; block state_path_escape;; esac
PATH_GUARDS="PASS"

PHASE="empty_verify"
DRAFT_COUNT="$(count_entries "$DRAFT_DIR")"
SCHEDULED_COUNT="$(count_entries "$SCHEDULED_DIR")"
STATE_COUNT="$(count_entries "$STATE_DIR")"
[ "$DRAFT_COUNT" -eq 0 ] || { ERROR_CLASS="draft_runtime_not_empty"; block draft_runtime_not_empty; }
[ "$SCHEDULED_COUNT" -eq 0 ] || { ERROR_CLASS="scheduled_runtime_not_empty"; block scheduled_runtime_not_empty; }
[ "$STATE_COUNT" -eq 0 ] || { ERROR_CLASS="publisher_state_runtime_not_empty"; block publisher_state_runtime_not_empty; }

PHASE="final_safety"
LEGACY_AFTER="$(count_json "$LEGACY_QUEUE")"
CRON_AFTER="$(cron_count)"
[ "$LEGACY_AFTER" -eq "$LEGACY_BEFORE" ] || { ERROR_CLASS="legacy_queue_changed"; block legacy_queue_changed; }
[ "$CRON_AFTER" -eq "$CRON_BEFORE" ] && [ "$CRON_AFTER" -eq 0 ] || { ERROR_CLASS="publisher_cron_changed"; block publisher_cron_changed; }
POLICY_ENABLED_AFTER=$(php -r '$x=json_decode(file_get_contents($argv[1]),true); echo (($x["publishing_enabled"]??null)===true)?"yes":"no";' "$POLICY")
[ "$POLICY_ENABLED_AFTER" = "no" ] || { ERROR_CLASS="publication_policy_changed"; block publication_policy_changed; }

PHASE="final"
trap - ERR
STATUS="PASS"
ERROR_CLASS="NONE"
BLOCKING_ITEM="NONE"
write_payload PASS
echo "PREPARE_CF50_RUNTIME_V1=PASS"
