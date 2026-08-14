#!/bin/bash
# Activate the isolated CF50 first-wave Publisher cron after fail-closed runtime verification.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
RUNTIME_ROOT="/var/lib/xyptdq-content/CF50-20260813-wave1"
DRAFT_DIR="$RUNTIME_ROOT/drafts"
SCHEDULED_DIR="$RUNTIME_ROOT/scheduled"
LEGACY_QUEUE="$REPO/content/scheduled"
POLICY="$REPO/config/content_publication_policy.json"
INSTALLER="$REPO/scripts/content/install_publisher_cron.sh"
CRON_FILE="/etc/cron.d/xyptdq-publisher"
STATE_PATH="/var/lib/xyptdq-publisher/CF50-20260813-wave1/state.json"
LOCK_PATH="/var/lib/xyptdq-publisher/CF50-20260813-wave1/publisher.lock"
EXPECTED_INTAKE_MODE="public_release_transfer_canary"

[ -n "$RESULT_FILE" ] || exit 2
[ "$(id -u)" -eq 0 ] || exit 3
[ -d "$REPO/.git" ] || exit 4

cron_count(){
  local n=0
  [ -f "$CRON_FILE" ] && n=$((n+1))
  local user_hits
  user_hits=$( (crontab -l 2>/dev/null || true) | grep -c 'run_scheduled_publish.sh' || true )
  echo $((n + user_hits))
}

write_result(){
  local status="$1" blocker="$2" cron="$3"
  python3 - "$RESULT_FILE" "$status" "$blocker" "$cron" <<'PY'
import json,sys
out,status,blocker,cron=sys.argv[1:]
p={
 "task":"activate_cf50_wave1_recurring_v2",
 "status":status,
 "blocking_item":blocker,
 "runtime_root":"/var/lib/xyptdq-content/CF50-20260813-wave1",
 "draft_count_expected":11,
 "scheduled_count_expected":11,
 "legacy_repository_scheduled_count_expected":11,
 "publisher_cron_count":int(cron),
 "source_queue":"/var/lib/xyptdq-content/CF50-20260813-wave1/scheduled",
 "state_path":"/var/lib/xyptdq-publisher/CF50-20260813-wave1/state.json",
 "lock_path":"/var/lib/xyptdq-publisher/CF50-20260813-wave1/publisher.lock",
 "expected_source_intake_mode":"public_release_transfer_canary",
 "legacy_queue_consumed":False,
 "cms_write_attempted":False,
 "wave_b_authorized":False
}
with open(out,'w',encoding='utf-8') as f:
 json.dump(p,f,ensure_ascii=False,indent=2,sort_keys=True); f.write('\n')
PY
}

CRON_INSTALLED_BY_TASK="NO"
rollback(){
  set +e
  if [ "$CRON_INSTALLED_BY_TASK" = "YES" ]; then rm -f "$CRON_FILE"; fi
  set -e
}
fail_closed(){
  local item="$1"
  rollback
  local cc
  cc="$(cron_count)"
  write_result "BLOCKED" "$item" "$cc"
  echo "ACTIVATE_CF50_WAVE1_RECURRING_V2=BLOCKED item=$item" >&2
  exit 10
}

[ -z "$(git -C "$REPO" status --porcelain 2>/dev/null)" ] || fail_closed production_repo_dirty
git -C "$REPO" fetch --quiet origin main || fail_closed git_fetch_failed
git -C "$REPO" checkout -q main || fail_closed checkout_main_failed
git -C "$REPO" reset --hard -q origin/main || fail_closed reset_to_origin_main_failed

[ -f "$POLICY" ] || fail_closed publication_policy_missing
[ -f "$INSTALLER" ] || fail_closed cron_installer_file_missing

if ! php - "$POLICY" "$SCHEDULED_DIR" "$STATE_PATH" "$LOCK_PATH" <<'PHP'
<?php
$x=json_decode(file_get_contents($argv[1]),true);
if (!is_array($x) || ($x['publishing_enabled']??null)!==true) exit(1);
if (($x['mode']??null)!=='wave1_recurring_activation_authorized') exit(2);
$r=$x['runtime_rules']??[];
if (($r['runtime_source_root']??null)!==$argv[2]) exit(3);
if (($r['runtime_state_path']??null)!==$argv[3]) exit(4);
if (($r['runtime_lock_path']??null)!==$argv[4]) exit(5);
if (($r['legacy_repository_queue_forbidden']??null)!==true) exit(6);
if ((int)($r['expected_isolated_scheduled_count']??0)!==11) exit(7);
if (($r['recurring_cron_allowed_now']??null)!==true) exit(8);
PHP
then
  fail_closed publication_policy_contract_mismatch
fi

DRAFT_COUNT=$(find "$DRAFT_DIR" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
SCHEDULED_COUNT=$(find "$SCHEDULED_DIR" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
LEGACY_COUNT=$(find "$LEGACY_QUEUE" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
[ "$DRAFT_COUNT" -eq 11 ] || fail_closed draft_count_not_11
[ "$SCHEDULED_COUNT" -eq 11 ] || fail_closed scheduled_count_not_11
[ "$LEGACY_COUNT" -eq 11 ] || fail_closed legacy_repository_scheduled_count_changed
[ "$(cron_count)" -eq 0 ] || fail_closed publisher_cron_already_present

resolved=$(realpath "$SCHEDULED_DIR")
case "$resolved" in /var/lib/xyptdq-content/*) ;; *) fail_closed runtime_source_outside_isolated_root ;; esac

python3 - "$DRAFT_DIR" "$SCHEDULED_DIR" "$EXPECTED_INTAKE_MODE" <<'PY' || fail_closed runtime_schedule_or_metadata_mismatch
import json,pathlib,sys
from datetime import datetime
expected=[
("LCM-CREATOR-cf50-20260813-011","2026-08-14T19:00:00+08:00"),
("LCM-CREATOR-cf50-20260813-021","2026-08-15T10:00:00+08:00"),
("LCM-CREATOR-cf50-20260813-031","2026-08-15T19:00:00+08:00"),
("LCM-CREATOR-cf50-20260813-041","2026-08-16T10:00:00+08:00"),
("LCM-CREATOR-cf50-20260813-046","2026-08-16T19:00:00+08:00"),
("LCM-CREATOR-cf50-20260813-002","2026-08-17T10:00:00+08:00"),
("LCM-CREATOR-cf50-20260813-012","2026-08-17T19:00:00+08:00"),
("LCM-CREATOR-cf50-20260813-022","2026-08-18T10:00:00+08:00"),
("LCM-CREATOR-cf50-20260813-032","2026-08-18T19:00:00+08:00"),
("LCM-CREATOR-cf50-20260813-037","2026-08-19T10:00:00+08:00"),
("LCM-CREATOR-cf50-20260813-049","2026-08-19T19:00:00+08:00")]
dr,sr=map(pathlib.Path,sys.argv[1:3]); intake=sys.argv[3]
for aid,when in expected:
 dp=dr/f'{aid}.json'; sp=sr/f'{aid}.json'
 if not dp.is_file() or not sp.is_file(): raise SystemExit(1)
 d=json.loads(dp.read_text(encoding='utf-8')); s=json.loads(sp.read_text(encoding='utf-8'))
 if d.get('article_id')!=aid or d.get('publication_state')!='draft' or 'publish_at' in d: raise SystemExit(2)
 if s.get('article_id')!=aid or s.get('publication_state')!='scheduled' or s.get('publish_at')!=when: raise SystemExit(3)
 datetime.fromisoformat(when)
 for x in (d,s):
  if x.get('site_category_key')!='tzjq' or int(x.get('catid',0))!=3: raise SystemExit(4)
  if x.get('primary_seo_cluster_id')!='ffc_research': raise SystemExit(5)
  if x.get('source_revision_id')!=aid+':public-r1': raise SystemExit(6)
  if x.get('source_intake_mode')!=intake: raise SystemExit(7)
 for key in ('source_content_hash','source_fingerprint','source_parent_content_hash','source_parent_fingerprint','slug','primary_keyword'):
  if d.get(key)!=s.get(key): raise SystemExit(8)
PY

install -d -o root -g www-data -m 0750 "$(dirname "$STATE_PATH")"
XYPTDQ_REPO_DIR="$REPO" \
XYPTDQ_PUBLISH_SOURCE="$SCHEDULED_DIR" \
XYPTDQ_PUBLISH_STATE="$STATE_PATH" \
XYPTDQ_PUBLISH_LOCK="$LOCK_PATH" \
  bash "$INSTALLER" "$REPO" "$SCHEDULED_DIR" "$STATE_PATH" "$LOCK_PATH" >/dev/null || fail_closed cron_install_failed
CRON_INSTALLED_BY_TASK="YES"

[ "$(cron_count)" -eq 1 ] || fail_closed publisher_cron_count_not_1_after_install
[ -f "$CRON_FILE" ] || fail_closed publisher_cron_file_missing
grep -Fq "XYPTDQ_PUBLISH_SOURCE=$SCHEDULED_DIR" "$CRON_FILE" || fail_closed cron_source_binding_missing
grep -Fq "XYPTDQ_PUBLISH_STATE=$STATE_PATH" "$CRON_FILE" || fail_closed cron_state_binding_missing
grep -Fq "XYPTDQ_PUBLISH_LOCK=$LOCK_PATH" "$CRON_FILE" || fail_closed cron_lock_binding_missing
grep -Fq '7 * * * *' "$CRON_FILE" || fail_closed cron_schedule_not_minute_7

LEGACY_AFTER=$(find "$LEGACY_QUEUE" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
[ "$LEGACY_AFTER" -eq 11 ] || fail_closed legacy_repository_queue_changed_during_activation

write_result "PASS" "NONE" "1"
echo "ACTIVATE_CF50_WAVE1_RECURRING_V2=PASS cron=1 scheduled=11 legacy=11"
