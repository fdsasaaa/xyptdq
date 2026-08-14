#!/bin/bash
# Stage the remaining 11 CF50 first-wave public releases into an isolated Draft/Scheduled runtime.
# This task never enables publishing, installs cron, writes CMS content, or touches the legacy repository Scheduled queue.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
RUNTIME_ROOT="/var/lib/xyptdq-content/CF50-20260813-wave1"
DRAFT_DIR="$RUNTIME_ROOT/drafts"
SCHEDULED_DIR="$RUNTIME_ROOT/scheduled"
INGRESS_DIR="$REPO/content/ingress/public-release/CF50-20260813"
PARENT_INDEX="$INGRESS_DIR/parent-identity-index.json"
MANIFEST="$INGRESS_DIR/manifest.json"
CLUSTER_MAP="$REPO/content/seo_editorial_cluster_map_cf50.json"
POLICY="$REPO/config/content_publication_policy.json"
LEGACY_QUEUE="$REPO/content/scheduled"
BATCH_INGEST="$REPO/scripts/content/ingest_public_release_transfer_batch.php"
PROMOTE="$REPO/scripts/content/promote_draft.php"

IDS=(
  LCM-CREATOR-cf50-20260813-011
  LCM-CREATOR-cf50-20260813-021
  LCM-CREATOR-cf50-20260813-031
  LCM-CREATOR-cf50-20260813-041
  LCM-CREATOR-cf50-20260813-046
  LCM-CREATOR-cf50-20260813-002
  LCM-CREATOR-cf50-20260813-012
  LCM-CREATOR-cf50-20260813-022
  LCM-CREATOR-cf50-20260813-032
  LCM-CREATOR-cf50-20260813-037
  LCM-CREATOR-cf50-20260813-049
)
TIMES=(
  2026-08-14T19:00:00+08:00
  2026-08-15T10:00:00+08:00
  2026-08-15T19:00:00+08:00
  2026-08-16T10:00:00+08:00
  2026-08-16T19:00:00+08:00
  2026-08-17T10:00:00+08:00
  2026-08-17T19:00:00+08:00
  2026-08-18T10:00:00+08:00
  2026-08-18T19:00:00+08:00
  2026-08-19T10:00:00+08:00
  2026-08-19T19:00:00+08:00
)

PHASE="init"
STATUS="BLOCKED"
DRAFT_COUNT=0
SCHEDULED_COUNT=0
LEGACY_COUNT=-1
CRON_COUNT=-1
BLOCKING_ITEM="NONE"

[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3

write_result(){ python3 - "$RESULT_FILE" "$STATUS" "$PHASE" "$DRAFT_COUNT" "$SCHEDULED_COUNT" "$LEGACY_COUNT" "$CRON_COUNT" "$BLOCKING_ITEM" "$RUNTIME_ROOT" <<'PY'
import json,sys
out,status,phase,drafts,scheduled,legacy,cron,blocker,runtime=sys.argv[1:]
p={
  "task":"stage_cf50_wave1_schedule_v1",
  "status":status,
  "phase":phase,
  "batch_id":"CF50-20260813",
  "already_live_article_id":"LCM-CREATOR-cf50-20260813-001",
  "staged_article_count":int(drafts),
  "scheduled_article_count":int(scheduled),
  "legacy_repository_scheduled_count":int(legacy),
  "publisher_cron_count":int(cron),
  "runtime_root":runtime,
  "publishing_enabled_expected":False,
  "cms_write_attempted":False,
  "publisher_run_attempted":False,
  "legacy_repository_queue_consumed":False,
  "blocking_item":blocker,
  "schedule_timezone":"Asia/Singapore",
  "release_slots":[
    "2026-08-14T19:00:00+08:00","2026-08-15T10:00:00+08:00","2026-08-15T19:00:00+08:00",
    "2026-08-16T10:00:00+08:00","2026-08-16T19:00:00+08:00","2026-08-17T10:00:00+08:00",
    "2026-08-17T19:00:00+08:00","2026-08-18T10:00:00+08:00","2026-08-18T19:00:00+08:00",
    "2026-08-19T10:00:00+08:00","2026-08-19T19:00:00+08:00"
  ]
}
with open(out,'w',encoding='utf-8') as f:
    json.dump(p,f,ensure_ascii=False,indent=2,sort_keys=True); f.write('\n')
PY
}

block(){ BLOCKING_ITEM="$1"; STATUS="BLOCKED"; write_result; echo "[cf50-wave1-stage] BLOCKED: $1" >&2; exit 1; }

cron_count(){
  local n=0
  [ -f /etc/cron.d/xyptdq-publisher ] && n=$((n+1))
  local user_hits
  user_hits=$( (crontab -l 2>/dev/null || true) | grep -c 'run_scheduled_publish.sh' || true )
  echo $((n + user_hits))
}

PHASE="sync_main"
cd "$REPO"
[ -z "$(git status --porcelain)" ] || block production_repo_dirty
git fetch --prune origin >/dev/null 2>&1
git reset --hard origin/main >/dev/null

PHASE="preflight"
[ -f "$POLICY" ] || block publication_policy_missing
POLICY_ENABLED=$(php -r '$x=json_decode(file_get_contents($argv[1]),true); echo (($x["publishing_enabled"]??null)===true)?"yes":"no";' "$POLICY")
[ "$POLICY_ENABLED" = "no" ] || block publication_policy_must_remain_disabled_during_staging
CRON_COUNT="$(cron_count)"
[ "$CRON_COUNT" -eq 0 ] || block publisher_cron_must_be_absent_during_staging
LEGACY_COUNT=$(find "$LEGACY_QUEUE" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
[ "$LEGACY_COUNT" -eq 11 ] || block legacy_repository_scheduled_count_changed
[ -f "$INGRESS_DIR/LCM-CREATOR-cf50-20260813-011.public-r1.json" ] || block safe_ingress_missing
[ -f "$BATCH_INGEST" ] && [ -f "$PROMOTE" ] || block intake_or_promote_script_missing

PHASE="runtime_prepare"
if [ -d "$RUNTIME_ROOT" ]; then
  existing=$(find "$RUNTIME_ROOT" -type f 2>/dev/null | wc -l | tr -d ' ')
  [ "$existing" -eq 0 ] || block runtime_root_not_empty
fi
install -d -o root -g www-data -m 0750 "$RUNTIME_ROOT" "$DRAFT_DIR" "$SCHEDULED_DIR"

PHASE="draft_ingest"
IDS_CSV=$(IFS=,; echo "${IDS[*]}")
php "$BATCH_INGEST" \
  --ingress-dir="$INGRESS_DIR" \
  --parent-index="$PARENT_INDEX" \
  --manifest="$MANIFEST" \
  --editorial-cluster-map="$CLUSTER_MAP" \
  --output-dir="$DRAFT_DIR" \
  --article-ids="$IDS_CSV" >/dev/null
DRAFT_COUNT=$(find "$DRAFT_DIR" -maxdepth 1 -type f -name '*.json' | wc -l | tr -d ' ')
[ "$DRAFT_COUNT" -eq 11 ] || block expected_11_drafts

PHASE="promote_schedule"
for i in "${!IDS[@]}"; do
  id="${IDS[$i]}"
  when="${TIMES[$i]}"
  php "$PROMOTE" \
    --input="$DRAFT_DIR/$id.json" \
    --publish-at="$when" \
    --output="$SCHEDULED_DIR/$id.json" >/dev/null
done
SCHEDULED_COUNT=$(find "$SCHEDULED_DIR" -maxdepth 1 -type f -name '*.json' | wc -l | tr -d ' ')
[ "$SCHEDULED_COUNT" -eq 11 ] || block expected_11_scheduled

PHASE="verify_schedule"
python3 - "$SCHEDULED_DIR" <<'PY'
import json, pathlib, sys
root=pathlib.Path(sys.argv[1])
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
for article_id, when in expected:
    p=root/f"{article_id}.json"
    x=json.loads(p.read_text(encoding='utf-8'))
    assert x.get('article_id')==article_id
    assert x.get('publication_state')=='scheduled'
    assert x.get('publish_at')==when
    assert x.get('site_category_key')=='tzjq' and int(x.get('catid',0))==3
    assert x.get('primary_seo_cluster_id')=='ffc_research'
    assert x.get('source_revision_id')==article_id+':public-r1'
    assert x.get('source_intake_mode')=='sanitized_public_release_transfer'
PY

PHASE="safety_recheck"
LEGACY_AFTER=$(find "$LEGACY_QUEUE" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
[ "$LEGACY_AFTER" -eq 11 ] || block legacy_repository_queue_changed_during_staging
CRON_COUNT="$(cron_count)"
[ "$CRON_COUNT" -eq 0 ] || block publisher_cron_changed_during_staging
POLICY_ENABLED=$(php -r '$x=json_decode(file_get_contents($argv[1]),true); echo (($x["publishing_enabled"]??null)===true)?"yes":"no";' "$POLICY")
[ "$POLICY_ENABLED" = "no" ] || block publication_policy_changed_during_staging

PHASE="complete"
STATUS="PASS"
BLOCKING_ITEM="NONE"
write_result
echo "STAGE_CF50_WAVE1_SCHEDULE_V1=PASS drafts=$DRAFT_COUNT scheduled=$SCHEDULED_COUNT legacy=$LEGACY_COUNT cron=$CRON_COUNT"
