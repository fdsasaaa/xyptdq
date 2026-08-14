#!/bin/bash
# Read-only verification of the already staged CF50 first-wave runtime.
# The staged runtime was created by the validated transfer-canary primitive, so its
# persisted source_intake_mode is public_release_transfer_canary.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
RUNTIME_ROOT="/var/lib/xyptdq-content/CF50-20260813-wave1"
DRAFT_DIR="$RUNTIME_ROOT/drafts"
SCHEDULED_DIR="$RUNTIME_ROOT/scheduled"
POLICY="$REPO/config/content_publication_policy.json"
LEGACY_QUEUE="$REPO/content/scheduled"
CRON_FILE="/etc/cron.d/xyptdq-publisher"
EXPECTED_INTAKE_MODE="public_release_transfer_canary"

[ -n "$RESULT_FILE" ] || exit 2

cron_count(){
  local n=0
  [ -f "$CRON_FILE" ] && n=$((n+1))
  local user_hits
  user_hits=$( (crontab -l 2>/dev/null || true) | grep -c 'run_scheduled_publish.sh' || true )
  echo $((n + user_hits))
}

DRAFT_COUNT=$(find "$DRAFT_DIR" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
SCHEDULED_COUNT=$(find "$SCHEDULED_DIR" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
LEGACY_COUNT=$(find "$LEGACY_QUEUE" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
CRON_COUNT="$(cron_count)"
POLICY_ENABLED=$(php -r '$x=json_decode(file_get_contents($argv[1]),true); echo (($x["publishing_enabled"]??null)===true)?"true":"false";' "$POLICY")

STATUS="PASS"
BLOCKING_ITEM="NONE"
VERIFY_JSON="$(mktemp /tmp/xyptdq-wave1-verify-v2.XXXXXX.json)"
trap 'rm -f "$VERIFY_JSON"' EXIT

if [ "$DRAFT_COUNT" -ne 11 ]; then STATUS="BLOCKED"; BLOCKING_ITEM="draft_count_not_11"; fi
if [ "$SCHEDULED_COUNT" -ne 11 ]; then STATUS="BLOCKED"; BLOCKING_ITEM="scheduled_count_not_11"; fi
if [ "$LEGACY_COUNT" -ne 11 ]; then STATUS="BLOCKED"; BLOCKING_ITEM="legacy_queue_count_changed"; fi
if [ "$CRON_COUNT" -ne 0 ]; then STATUS="BLOCKED"; BLOCKING_ITEM="publisher_cron_not_zero"; fi
if [ "$POLICY_ENABLED" != "false" ]; then STATUS="BLOCKED"; BLOCKING_ITEM="publication_policy_not_disabled"; fi

if [ "$STATUS" = "PASS" ]; then
  if ! python3 - "$DRAFT_DIR" "$SCHEDULED_DIR" "$VERIFY_JSON" "$EXPECTED_INTAKE_MODE" <<'PY'
import json, pathlib, sys
from datetime import datetime

draft_root=pathlib.Path(sys.argv[1])
scheduled_root=pathlib.Path(sys.argv[2])
out=pathlib.Path(sys.argv[3])
expected_intake_mode=sys.argv[4]
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
("LCM-CREATOR-cf50-20260813-049","2026-08-19T19:00:00+08:00"),
]
seen=[]
for article_id, publish_at in expected:
    dp=draft_root/f"{article_id}.json"
    sp=scheduled_root/f"{article_id}.json"
    if not dp.is_file() or not sp.is_file():
        raise SystemExit(f"missing runtime file for {article_id}")
    d=json.loads(dp.read_text(encoding='utf-8'))
    s=json.loads(sp.read_text(encoding='utf-8'))
    if d.get('article_id') != article_id or d.get('publication_state') != 'draft' or 'publish_at' in d:
        raise SystemExit(f"draft lifecycle mismatch for {article_id}")
    if s.get('article_id') != article_id or s.get('publication_state') != 'scheduled':
        raise SystemExit(f"scheduled lifecycle mismatch for {article_id}")
    if s.get('publish_at') != publish_at:
        raise SystemExit(f"publish_at mismatch for {article_id}: {s.get('publish_at')}")
    datetime.fromisoformat(publish_at)
    for x,label in ((d,'draft'),(s,'scheduled')):
        if x.get('site_category_key') != 'tzjq' or int(x.get('catid',0)) != 3:
            raise SystemExit(f"category mismatch {label} {article_id}")
        if x.get('primary_seo_cluster_id') != 'ffc_research':
            raise SystemExit(f"cluster mismatch {label} {article_id}")
        if x.get('source_revision_id') != article_id+':public-r1':
            raise SystemExit(f"revision provenance mismatch {label} {article_id}")
        if x.get('source_intake_mode') != expected_intake_mode:
            raise SystemExit(f"source intake mismatch {label} {article_id}: {x.get('source_intake_mode')}")
    for key in ('source_content_hash','source_fingerprint','source_parent_content_hash','source_parent_fingerprint','slug','primary_keyword'):
        if d.get(key) != s.get(key):
            raise SystemExit(f"promotion changed {key} for {article_id}")
    seen.append({'article_id':article_id,'publish_at':publish_at,'source_intake_mode':expected_intake_mode})
out.write_text(json.dumps({'verified':seen},ensure_ascii=False),encoding='utf-8')
PY
  then
    STATUS="BLOCKED"
    BLOCKING_ITEM="runtime_schedule_or_metadata_mismatch"
  fi
fi

python3 - "$RESULT_FILE" "$STATUS" "$BLOCKING_ITEM" "$DRAFT_COUNT" "$SCHEDULED_COUNT" "$LEGACY_COUNT" "$CRON_COUNT" "$POLICY_ENABLED" "$VERIFY_JSON" "$EXPECTED_INTAKE_MODE" <<'PY'
import json, pathlib, sys
out,status,blocker,drafts,scheduled,legacy,cron,enabled,verify,intake=sys.argv[1:]
verified=[]
p=pathlib.Path(verify)
if p.is_file() and p.stat().st_size:
    try: verified=json.loads(p.read_text(encoding='utf-8')).get('verified',[])
    except Exception: verified=[]
payload={
  'task':'verify_cf50_wave1_schedule_v2',
  'status':status,
  'read_only':True,
  'runtime_root':'/var/lib/xyptdq-content/CF50-20260813-wave1',
  'draft_count':int(drafts),
  'scheduled_count':int(scheduled),
  'legacy_repository_scheduled_count':int(legacy),
  'publisher_cron_count':int(cron),
  'publishing_enabled': enabled=='true',
  'schedule_timezone':'Asia/Singapore',
  'expected_source_intake_mode':intake,
  'verified_schedule':verified,
  'blocking_item':blocker,
  'cms_write_attempted':False,
  'queue_consumed':False
}
with open(out,'w',encoding='utf-8') as f:
    json.dump(payload,f,ensure_ascii=False,indent=2,sort_keys=True); f.write('\n')
PY

if [ "$STATUS" != "PASS" ]; then
  echo "VERIFY_CF50_WAVE1_SCHEDULE_V2=BLOCKED item=$BLOCKING_ITEM" >&2
  exit 1
fi

echo "VERIFY_CF50_WAVE1_SCHEDULE_V2=PASS drafts=$DRAFT_COUNT scheduled=$SCHEDULED_COUNT legacy=$LEGACY_COUNT cron=$CRON_COUNT intake=$EXPECTED_INTAKE_MODE"
