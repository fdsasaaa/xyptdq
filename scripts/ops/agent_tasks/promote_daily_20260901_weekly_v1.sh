#!/bin/bash
# Auto Promotion Scheduler (weekly 2-3/day) for DAILY-20260901 wave.
# Promotes the next eligible Drafts from the isolated intake buffer into an isolated
# Scheduled queue with explicit weekly publish_at slots, then ensures the publisher
# cron consumes that queue. This task never writes CMS content directly; publication
# is exclusively performed by the existing native Xunrui publisher cron.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
INTAKE_DRAFTS="/var/lib/xyptdq-content/intake/drafts"
RUNTIME_ROOT="/var/lib/xyptdq-content/DAILY-20260901"
SCHEDULED_DIR="$RUNTIME_ROOT/scheduled"
POLICY="$REPO/config/content_publication_policy.json"
PROMOTE="$REPO/scripts/content/promote_draft.php"
PUBLISHER_CRON="${XYPTDQ_PUBLISHER_CRON:-/etc/cron.d/xyptdq-publisher}"
BATCH_ID="DAILY-20260901"
WEEKLY_SLOTS=("Tuesday" "Thursday" "Saturday")
MAX_PER_RUN=3

PHASE="init"
STATUS="BLOCKED"
SCHEDULED_COUNT=0
ADDED_COUNT=0
DRAFT_AVAILABLE=0
BLOCKING_ITEM="NONE"

[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3

write_result(){ python3 - "$RESULT_FILE" "$STATUS" "$PHASE" "$SCHEDULED_COUNT" "$ADDED_COUNT" "$DRAFT_AVAILABLE" "$BLOCKING_ITEM" "$BATCH_ID" "$SCHEDULED_DIR" <<'PY'
import json,sys
out,status,phase,sched,added,drafts,blocker,batch,runtime=sys.argv[1:]
p={
  "task":"promote_daily_20260901_weekly_v1",
  "status":status,
  "phase":phase,
  "batch_id":batch,
  "scheduled_count":int(sched),
  "added_this_run":int(added),
  "draft_available":int(drafts),
  "runtime_scheduled_dir":runtime,
  "cadence":"weekly_2_3",
  "cms_write_attempted":False,
  "publisher_run_attempted":False,
  "legacy_repository_queue_consumed":False,
  "blocking_item":blocker,
  "schedule_timezone":"Asia/Singapore"
}
with open(out,'w',encoding='utf-8') as f:
    json.dump(p,f,ensure_ascii=False,indent=2,sort_keys=True); f.write('\n')
PY
}

block(){ BLOCKING_ITEM="$1"; STATUS="BLOCKED"; write_result; echo "[daily-weekly-promote] BLOCKED: $1" >&2; exit 1; }

PHASE="sync_main"
cd "$REPO"
[ -z "$(git status --porcelain)" ] || block production_repo_dirty
git fetch --prune origin >/dev/null 2>&1
git reset --hard origin/main >/dev/null

PHASE="preflight"
[ -f "$POLICY" ] || block publication_policy_missing
MODE=$(php -r '$x=json_decode(file_get_contents($argv[1]),true); echo (($x["weekly_promotion_wave"]["mode"]??null)==="weekly_2_3_after_wave1_complete")?"ok":"bad";' "$POLICY")
[ "$MODE" = ok ] || block weekly_wave_not_authorized_in_policy
[ -f "$PROMOTE" ] || block promote_script_missing
[ -d "$INTAKE_DRAFTS" ] || block intake_draft_buffer_missing
DRAFT_AVAILABLE=$(find "$INTAKE_DRAFTS" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
[ "$DRAFT_AVAILABLE" -ge 1 ] || block no_drafts_in_intake_buffer

PHASE="runtime_prepare"
install -d -o root -g www-data -m 0750 "$RUNTIME_ROOT" "$SCHEDULED_DIR"
SCHEDULED_COUNT=$(find "$SCHEDULED_DIR" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' ')

# Already scheduled (future publish_at) items count against the weekly cap.
if [ "$SCHEDULED_COUNT" -ge "$MAX_PER_RUN" ]; then
  PHASE="complete"; STATUS="PASS"; BLOCKING_ITEM="NONE"
  write_result; echo "DAILY_WEEKLY_PROMOTE=PASS(already_scheduled=$SCHEDULED_COUNT)"
  exit 0
fi

PHASE="compute_slots"
SLOTS=$(python3 - "$MAX_PER_RUN" <<'PY'
import datetime, sys
zone = datetime.timezone(datetime.timedelta(hours=8))
now = datetime.datetime.now(zone)
days = {"Tuesday":1,"Thursday":3,"Saturday":5}
names = sys.argv[1].split(",") if False else ["Tuesday","Thursday","Saturday"]
order = {"Tuesday":0,"Thursday":1,"Saturday":2}
# next occurrence of each weekday, starting strictly in the future
slots=[]
for i in range(14):
    d = now + datetime.timedelta(days=i)
    if d.strftime("%A") in days and d > now:
        at = d.replace(hour=10, minute=0, second=0, microsecond=0)
        if at > now:
            slots.append(at.isoformat())
print("\n".join(slots[:int(sys.argv[2]) if False else 3]))
PY
)

PHASE="promote_schedule"
NEW_SCHEDULED=0
for id in $(python3 - "$INTAKE_DRAFTS" "$BATCH_ID" "$SCHEDULED_DIR" <<'PY'
import json, pathlib, sys
drafts_root, batch, sched_root = pathlib.Path(sys.argv[1]), sys.argv[2], pathlib.Path(sys.argv[3])
already = {p.stem for p in sched_root.glob("*.json")}
cands = []
for p in sorted(drafts_root.glob("*.json")):
    try:
        x = json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        continue
    if x.get("source_batch_id") != batch:
        continue
    if x.get("article_id") in already:
        continue
    cands.append(x["article_id"])
print("\n".join(cands))
PY
); do
  if [ "$NEW_SCHEDULED" -ge "$MAX_PER_RUN" ]; then break; fi
  when=$(printf '%s\n' "$SLOTS" | sed -n "$((NEW_SCHEDULED+1))p")
  [ -n "$when" ] || break
  php "$PROMOTE" --input="$INTAKE_DRAFTS/$id.json" --publish-at="$when" --output="$SCHEDULED_DIR/$id.json" >/dev/null
  NEW_SCHEDULED=$((NEW_SCHEDULED+1))
done
ADDED_COUNT=$NEW_SCHEDULED
SCHEDULED_COUNT=$(find "$SCHEDULED_DIR" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
[ "$SCHEDULED_COUNT" -ge 1 ] || block no_scheduled_items_after_promotion

PHASE="verify_schedule"
python3 - "$SCHEDULED_DIR" <<'PY'
import json, pathlib, sys, datetime
root = pathlib.Path(sys.argv[1])
zone = datetime.timezone(datetime.timedelta(hours=8))
now = datetime.datetime.now(zone)
count = 0
for p in root.glob("*.json"):
    x = json.loads(p.read_text(encoding="utf-8"))
    assert x.get("publication_state") == "scheduled"
    assert x.get("site_category_key") == "tzjq"
    assert x.get("source_batch_id") == "DAILY-20260901"
    when = datetime.datetime.fromisoformat(x["publish_at"])
    assert when > now, "scheduled publish_at must be in the future"
    count += 1
assert count >= 1
PY

PHASE="ensure_publisher_cron_source"
if [ -f "$PUBLISHER_CRON" ]; then
  if grep -q "XYPTDQ_PUBLISH_SOURCE=$SCHEDULED_DIR" "$PUBLISHER_CRON"; then
    :
  else
    sed -i "s|XYPTDQ_PUBLISH_SOURCE=[^ ]*|XYPTDQ_PUBLISH_SOURCE=$SCHEDULED_DIR|" "$PUBLISHER_CRON" || block publisher_cron_patch_failed
    grep -q "XYPTDQ_PUBLISH_SOURCE=$SCHEDULED_DIR" "$PUBLISHER_CRON" || block publisher_cron_patch_not_verified
  fi
else
  # Publisher cron absent: leave it absent (publication stays paused by absence);
  # scheduling is still valid and will be picked up when the cron is installed.
  :
fi

PHASE="complete"
STATUS="PASS"
BLOCKING_ITEM="NONE"
write_result
echo "DAILY_WEEKLY_PROMOTE=PASS added=$ADDED_COUNT scheduled=$SCHEDULED_COUNT drafts_available=$DRAFT_AVAILABLE"
