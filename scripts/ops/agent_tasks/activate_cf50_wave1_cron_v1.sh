#!/bin/bash
# Activate the isolated CF50 first-wave Publisher cron only after runtime staging is complete.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
SOURCE="/var/lib/xyptdq-content/CF50-20260813-wave1/scheduled"
STATE="/var/lib/xyptdq-publisher/cf50-wave1-state.json"
LOCK="/var/lib/xyptdq-publisher/cf50-wave1.lock"
POLICY="$REPO/config/content_publication_policy.json"
INSTALLER="$REPO/scripts/content/install_publisher_cron.sh"
LEGACY_QUEUE="$REPO/content/scheduled"
CRON_FILE="/etc/cron.d/xyptdq-publisher"

PHASE="init"
STATUS="BLOCKED"
SCHEDULED_COUNT=0
LEGACY_COUNT=-1
CRON_BEFORE=-1
CRON_AFTER=-1
BLOCKING_ITEM="NONE"
CRON_INSTALLED_BY_TASK="NO"

[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3

write_result(){ python3 - "$RESULT_FILE" "$STATUS" "$PHASE" "$SCHEDULED_COUNT" "$LEGACY_COUNT" "$CRON_BEFORE" "$CRON_AFTER" "$BLOCKING_ITEM" "$SOURCE" "$STATE" "$LOCK" <<'PY'
import json,sys
out,status,phase,scheduled,legacy,before,after,blocker,source,state,lock=sys.argv[1:]
p={
  "task":"activate_cf50_wave1_cron_v1",
  "status":status,
  "phase":phase,
  "batch_id":"CF50-20260813",
  "scheduled_article_count":int(scheduled),
  "legacy_repository_scheduled_count":int(legacy),
  "publisher_cron_count_before":int(before),
  "publisher_cron_count_after":int(after),
  "runtime_source":source,
  "runtime_state":state,
  "runtime_lock":lock,
  "publishing_enabled_expected":True,
  "publisher_check_schedule":"minute 7 of every hour",
  "publisher_limit_per_run":2,
  "legacy_repository_queue_consumed":False,
  "cms_write_attempted_by_activation_task":False,
  "blocking_item":blocker,
  "wave_b_authorized":False
}
with open(out,'w',encoding='utf-8') as f:
    json.dump(p,f,ensure_ascii=False,indent=2,sort_keys=True); f.write('\n')
PY
}

cron_count(){
  local n=0
  [ -f "$CRON_FILE" ] && n=$((n+1))
  local user_hits
  user_hits=$( (crontab -l 2>/dev/null || true) | grep -c 'run_scheduled_publish.sh' || true )
  echo $((n + user_hits))
}

rollback(){
  set +e
  if [ "$CRON_INSTALLED_BY_TASK" = "YES" ]; then
    rm -f "$CRON_FILE"
  fi
  CRON_AFTER="$(cron_count)"
  set -e
}

block(){
  BLOCKING_ITEM="$1"
  STATUS="BLOCKED"
  rollback
  write_result
  echo "[cf50-wave1-activate] BLOCKED: $1" >&2
  exit 1
}

PHASE="sync_main"
cd "$REPO"
[ -z "$(git status --porcelain)" ] || block production_repo_dirty
git fetch --prune origin >/dev/null 2>&1
git reset --hard origin/main >/dev/null

PHASE="policy_verify"
[ -f "$POLICY" ] || block publication_policy_missing
if ! php - "$POLICY" "$SOURCE" "$STATE" "$LOCK" <<'PHP'
<?php
$x=json_decode(file_get_contents($argv[1]),true);
if (!is_array($x) || ($x['publishing_enabled']??null)!==true) exit(1);
if (($x['mode']??null)!=='cf50_first_wave_recurring_controlled') exit(2);
$r=$x['runtime_rules']??[];
if (($r['runtime_source_root']??null)!==$argv[2]) exit(3);
if (($r['runtime_state_file']??null)!==$argv[3]) exit(4);
if (($r['runtime_lock_file']??null)!==$argv[4]) exit(5);
if (($r['legacy_repository_queue_forbidden']??null)!==true) exit(6);
if (($x['post_first_wave_gate']['wave_b_scheduling_allowed_before_checkpoint']??null)!==false) exit(7);
PHP
then
  block publication_policy_contract_mismatch
fi

PHASE="runtime_verify"
[ -d "$SOURCE" ] || block first_wave_scheduled_runtime_missing
SCHEDULED_COUNT=$(find "$SOURCE" -maxdepth 1 -type f -name '*.json' | wc -l | tr -d ' ')
[ "$SCHEDULED_COUNT" -eq 11 ] || block expected_11_first_wave_scheduled_files
python3 - "$SOURCE" <<'PY'
import json,pathlib,sys
root=pathlib.Path(sys.argv[1])
expected={
"LCM-CREATOR-cf50-20260813-011","LCM-CREATOR-cf50-20260813-021","LCM-CREATOR-cf50-20260813-031",
"LCM-CREATOR-cf50-20260813-041","LCM-CREATOR-cf50-20260813-046","LCM-CREATOR-cf50-20260813-002",
"LCM-CREATOR-cf50-20260813-012","LCM-CREATOR-cf50-20260813-022","LCM-CREATOR-cf50-20260813-032",
"LCM-CREATOR-cf50-20260813-037","LCM-CREATOR-cf50-20260813-049"}
seen=set()
for p in root.glob('*.json'):
 x=json.loads(p.read_text(encoding='utf-8'))
 aid=x.get('article_id')
 assert aid in expected and aid not in seen
 assert x.get('publication_state')=='scheduled'
 assert x.get('site_category_key')=='tzjq' and int(x.get('catid',0))==3
 assert x.get('primary_seo_cluster_id')=='ffc_research'
 assert x.get('source_revision_id')==aid+':public-r1'
 seen.add(aid)
assert seen==expected
PY

LEGACY_COUNT=$(find "$LEGACY_QUEUE" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
[ "$LEGACY_COUNT" -eq 11 ] || block legacy_repository_scheduled_count_changed
resolved=$(realpath "$SOURCE")
case "$resolved" in /var/lib/xyptdq-content/*) ;; *) block runtime_source_outside_isolated_root ;; esac

PHASE="cron_preflight"
CRON_BEFORE="$(cron_count)"
[ "$CRON_BEFORE" -eq 0 ] || block publisher_cron_already_present
[ -x "$INSTALLER" ] || block cron_installer_missing_or_not_executable

PHASE="cron_install"
"$INSTALLER" "$REPO" "$SOURCE" "$STATE" "$LOCK" >/dev/null
CRON_INSTALLED_BY_TASK="YES"
CRON_AFTER="$(cron_count)"
[ "$CRON_AFTER" -eq 1 ] || block publisher_cron_count_after_install_not_one
[ -f "$CRON_FILE" ] || block publisher_cron_file_missing

grep -Fq "XYPTDQ_PUBLISH_SOURCE=$SOURCE" "$CRON_FILE" || block cron_source_binding_missing
grep -Fq "XYPTDQ_PUBLISH_STATE=$STATE" "$CRON_FILE" || block cron_state_binding_missing
grep -Fq "XYPTDQ_PUBLISH_LOCK=$LOCK" "$CRON_FILE" || block cron_lock_binding_missing
grep -Fq '7 * * * *' "$CRON_FILE" || block cron_schedule_not_minute_7

PHASE="safety_recheck"
LEGACY_AFTER=$(find "$LEGACY_QUEUE" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
[ "$LEGACY_AFTER" -eq 11 ] || block legacy_repository_queue_changed_during_activation

PHASE="complete"
STATUS="PASS"
BLOCKING_ITEM="NONE"
write_result
echo "ACTIVATE_CF50_WAVE1_CRON_V1=PASS scheduled=$SCHEDULED_COUNT cron_before=$CRON_BEFORE cron_after=$CRON_AFTER legacy=$LEGACY_COUNT"
