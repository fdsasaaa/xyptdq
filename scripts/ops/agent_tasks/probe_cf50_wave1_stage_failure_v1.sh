#!/bin/bash
# Read-only probe after CF50 wave1 staging failure. No file, policy, cron, queue, or CMS mutation.
set -u
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
RUNTIME_ROOT="/var/lib/xyptdq-content/CF50-20260813-wave1"
DRAFT_DIR="$RUNTIME_ROOT/drafts"
SCHEDULED_DIR="$RUNTIME_ROOT/scheduled"
POLICY="$REPO/config/content_publication_policy.json"
LEGACY_QUEUE="$REPO/content/scheduled"
CRON_FILE="/etc/cron.d/xyptdq-publisher"

[ -n "$RESULT_FILE" ] || exit 2

count_json(){
  local dir="$1"
  if [ -d "$dir" ]; then
    find "$dir" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' '
  else
    echo 0
  fi
}

DRAFT_COUNT="$(count_json "$DRAFT_DIR")"
SCHEDULED_COUNT="$(count_json "$SCHEDULED_DIR")"
LEGACY_COUNT="$(count_json "$LEGACY_QUEUE")"
POLICY_ENABLED="unknown"
POLICY_MODE="unknown"
if [ -f "$POLICY" ]; then
  POLICY_ENABLED=$(php -r '$x=json_decode(file_get_contents($argv[1]),true); echo (($x["publishing_enabled"]??null)===true)?"true":"false";' "$POLICY" 2>/dev/null || echo invalid)
  POLICY_MODE=$(php -r '$x=json_decode(file_get_contents($argv[1]),true); echo (string)($x["mode"]??"unknown");' "$POLICY" 2>/dev/null || echo invalid)
fi
CRON_COUNT=0
[ -f "$CRON_FILE" ] && CRON_COUNT=$((CRON_COUNT+1))
USER_CRON=$( (crontab -l 2>/dev/null || true) | grep -c 'run_scheduled_publish.sh' || true )
CRON_COUNT=$((CRON_COUNT + USER_CRON))
REPO_HEAD="unknown"
REPO_DIRTY="unknown"
if [ -d "$REPO/.git" ]; then
  REPO_HEAD=$(git -C "$REPO" rev-parse HEAD 2>/dev/null || echo unknown)
  if [ -n "$(git -C "$REPO" status --porcelain 2>/dev/null)" ]; then REPO_DIRTY=true; else REPO_DIRTY=false; fi
fi
DRAFT_IDS=""
SCHEDULED_IDS=""
if [ -d "$DRAFT_DIR" ]; then DRAFT_IDS=$(find "$DRAFT_DIR" -maxdepth 1 -type f -name '*.json' -printf '%f\n' 2>/dev/null | sed 's/\.json$//' | sort | paste -sd, -); fi
if [ -d "$SCHEDULED_DIR" ]; then SCHEDULED_IDS=$(find "$SCHEDULED_DIR" -maxdepth 1 -type f -name '*.json' -printf '%f\n' 2>/dev/null | sed 's/\.json$//' | sort | paste -sd, -); fi

python3 - "$RESULT_FILE" "$DRAFT_COUNT" "$SCHEDULED_COUNT" "$LEGACY_COUNT" "$POLICY_ENABLED" "$POLICY_MODE" "$CRON_COUNT" "$REPO_HEAD" "$REPO_DIRTY" "$DRAFT_IDS" "$SCHEDULED_IDS" <<'PY'
import json,sys
out,drafts,scheduled,legacy,enabled,mode,cron,head,dirty,draft_ids,scheduled_ids=sys.argv[1:]
p={
 "task":"probe_cf50_wave1_stage_failure_v1",
 "status":"PASS",
 "read_only":True,
 "runtime_root":"/var/lib/xyptdq-content/CF50-20260813-wave1",
 "draft_count":int(drafts),
 "scheduled_count":int(scheduled),
 "draft_article_ids":[x for x in draft_ids.split(',') if x],
 "scheduled_article_ids":[x for x in scheduled_ids.split(',') if x],
 "legacy_repository_scheduled_count":int(legacy),
 "publishing_enabled": enabled == 'true',
 "publication_policy_mode":mode,
 "publisher_cron_count":int(cron),
 "production_repo_head":head,
 "production_repo_dirty": dirty == 'true',
 "cms_write_attempted":False,
 "queue_consumed":False
}
with open(out,'w',encoding='utf-8') as f:
 json.dump(p,f,ensure_ascii=False,indent=2,sort_keys=True); f.write('\n')
PY

echo "PROBE_CF50_WAVE1_STAGE_FAILURE_V1=PASS drafts=$DRAFT_COUNT scheduled=$SCHEDULED_COUNT legacy=$LEGACY_COUNT policy=$POLICY_ENABLED cron=$CRON_COUNT"
