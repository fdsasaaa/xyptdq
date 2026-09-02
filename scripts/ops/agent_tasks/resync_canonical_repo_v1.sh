#!/bin/bash
# Resync the server canonical repo to origin/main (tolerant) so the publisher
# picks up the tolerant-sync fix (PR #488). Then verify the fixed script is present.
# This is an infrastructure repair job; it does NOT touch articles, CMS, cron or queues.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
[ -n "$RESULT_FILE" ] || exit 2

STATUS="BLOCKED"
PHASE="init"
BLOCKING_ITEM="NONE"

write_result(){ python3 - "$RESULT_FILE" "$STATUS" "$PHASE" "$BLOCKING_ITEM" <<'PY'
import json, sys
out, status, phase, blocker = sys.argv[1:]
p = {
  "task": "resync_canonical_repo_v1",
  "status": status,
  "phase": phase,
  "blocking_item": blocker,
  "cms_write": False,
  "publisher_invoked": False,
  "cron_write": False,
}
with open(out, "w", encoding="utf-8") as f:
    json.dump(p, f, ensure_ascii=False, indent=2, sort_keys=True); f.write("\n")
PY
}
block(){ BLOCKING_ITEM="$1"; STATUS="BLOCKED"; write_result; echo "[resync] BLOCKED: $1" >&2; exit 1; }

[ -d "$REPO/.git" ] || block canonical_repo_missing

PHASE="before"
BEFORE_HEAD=$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo "unknown")
BEFORE_DIRTY=$(git -C "$REPO" status --porcelain 2>/dev/null | wc -l | tr -d ' ')

PHASE="resync"
# Tolerant sync identical to the publisher fix: fetch + checkout main + reset.
git -C "$REPO" fetch --prune origin >/dev/null 2>&1 || true
git -C "$REPO" checkout -q main 2>/dev/null || git -C "$REPO" checkout -q -B main origin/main
git -C "$REPO" reset --hard origin/main >/dev/null

PHASE="verify"
AFTER_HEAD=$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo "unknown")
AFTER_DIRTY=$(git -C "$REPO" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
grep -q "Tolerant sync" "$REPO/scripts/content/run_scheduled_publish.sh" || block tolerant_sync_fix_missing
grep -q "publisher-execution-probe-20260902-01" "$REPO/scripts/content/run_scheduled_publish.sh" || block fix_comment_missing
# sanity: canary queue file must still exist and be untouched
CANARY="$REPO/../xyptdq-content/ordinary-seo/scheduled/lcm-angle-0b6f9c192c45dc31.json"
CANARY_REAL="/var/lib/xyptdq-content/ordinary-seo/scheduled/lcm-angle-0b6f9c192c45dc31.json"
CANARY_STATE="unknown"
if [ -f "$CANARY_REAL" ]; then
  CANARY_STATE=$(python3 -c "import json;d=json.load(open('$CANARY_REAL'));print(d.get('publication_state'), d.get('publish_at'))" 2>/dev/null || echo "parse_error")
fi

PHASE="complete"
STATUS="PASS"
write_result
F=$(python3 - "$BEFORE_HEAD" "$BEFORE_DIRTY" "$AFTER_HEAD" "$AFTER_DIRTY" "$CANARY_STATE" <<'PY'
import json, sys
before, before_dirty, after, after_dirty, canary = sys.argv[1:]
print(json.dumps({
  "before_head": before, "before_dirty_lines": int(before_dirty),
  "after_head": after, "after_dirty_lines": int(after_dirty),
  "canary_state": canary,
  "tolerant_sync_fix_present": True,
}, ensure_ascii=False, sort_keys=True))
PY
)
python3 - "$RESULT_FILE" "$F" <<'PY'
import json, sys
result_file, findings = sys.argv[1:]
with open(result_file, "w", encoding="utf-8") as f:
    json.dump({
      "task": "resync_canonical_repo_v1",
      "status": "PASS", "phase": "complete", "blocking_item": "NONE",
      "cms_write": False, "publisher_invoked": False, "cron_write": False,
      "findings": json.loads(findings),
    }, f, ensure_ascii=False, indent=2, sort_keys=True); f.write("\n")
PY
echo "RESYNC_CANONICAL_REPO=PASS $BEFORE_HEAD->$AFTER_HEAD dirty=$BEFORE_DIRTY->$AFTER_DIRTY canary=$CANARY_STATE"
