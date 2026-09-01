#!/bin/bash
# Hold recurring promotion cron (temporarily) + isolate publisher state to ordinary-seo.
# Preserves the scheduled canary #1 exactly. Runs only after the read-only safety probe PASS.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
STABLE_QUEUE="/var/lib/xyptdq-content/ordinary-seo/scheduled"
PUBLISHER_CRON="${XYPTDQ_PUBLISHER_CRON:-/etc/cron.d/xyptdq-publisher}"
PROMOTION_CRON="${XYPTDQ_PROMOTION_CRON:-/etc/cron.d/xyptdq-promotion}"
PUBLISHER_ROOT="/var/lib/xyptdq-publisher"
ORDINARY_STATE="$PUBLISHER_ROOT/ordinary-seo/state.json"
ORDINARY_LOCK="$PUBLISHER_ROOT/ordinary-seo/publisher.lock"

PHASE="init"
STATUS="BLOCKED"
BLOCKING_ITEM="NONE"

[ -n "$RESULT_FILE" ] || exit 2

write_result(){ python3 - "$RESULT_FILE" "$STATUS" "$PHASE" "$BLOCKING_ITEM" <<'PY'
import json, sys
out, status, phase, blocker = sys.argv[1:]
p = {
  "task": "hold_promotion_isolate_publisher_v1",
  "status": status,
  "phase": phase,
  "blocking_item": blocker,
  "cms_write": False,
  "publisher_invoked": False,
  "promotion_cron_held": False,
  "publisher_state_isolated": False,
}
with open(out, "w", encoding="utf-8") as f:
    json.dump(p, f, ensure_ascii=False, indent=2, sort_keys=True); f.write("\n")
PY
}

block(){ BLOCKING_ITEM="$1"; STATUS="BLOCKED"; write_result; echo "[hold-isolate] BLOCKED: $1" >&2; exit 1; }

PHASE="preflight"
[ -f "$PROMOTION_CRON" ] || block promotion_cron_missing
[ -f "$PUBLISHER_CRON" ] || block publisher_cron_missing
[ -d "$STABLE_QUEUE" ] || block stable_queue_missing
# canary must still exist BEFORE any mutation
CANARY_PRESENT=$(python3 - "$STABLE_QUEUE" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
for p in root.glob("*.json"):
    try:
        x = json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        continue
    if x.get("source_article_id") == "LCM-ANGLE-0b6f9c192c45dc31" and x.get("publication_state") == "scheduled":
        print("yes"); break
else:
    print("no")
PY
)
[ "$CANARY_PRESENT" = yes ] || block canary_not_present_before_mutation

PHASE="hold_promotion_cron"
TMP=$(mktemp /tmp/xyptdq-promotion-hold.XXXXXX)
trap 'rm -f "$TMP"' EXIT
sed -E 's/^([^#].*promote_ordinary_seo_v1\.sh.*)$/# HELD-20260902-E2E-CANARY \1/' "$PROMOTION_CRON" > "$TMP"
chmod 0644 "$TMP"
install -o root -g root -m 0644 "$TMP" "$PROMOTION_CRON"
ACTIVE_LINES=$(grep -c -E '^[^#].*promote_ordinary_seo_v1\.sh' "$PROMOTION_CRON" 2>/dev/null || echo 0)
[ "$ACTIVE_LINES" -eq 0 ] || block promotion_cron_still_active

PHASE="isolate_publisher_state"
mkdir -p "$PUBLISHER_ROOT/ordinary-seo"
chmod 750 "$PUBLISHER_ROOT/ordinary-seo"
# patch publisher cron env: SOURCE (verify), STATE, LOCK
sed -i "s|XYPTDQ_PUBLISH_SOURCE=[^ ]*|XYPTDQ_PUBLISH_SOURCE=$STABLE_QUEUE|" "$PUBLISHER_CRON" || block source_patch_failed
sed -i "s|XYPTDQ_PUBLISH_STATE=[^ ]*|XYPTDQ_PUBLISH_STATE=$ORDINARY_STATE|" "$PUBLISHER_CRON" || block state_patch_failed
sed -i "s|XYPTDQ_PUBLISH_LOCK=[^ ]*|XYPTDQ_PUBLISH_LOCK=$ORDINARY_LOCK|" "$PUBLISHER_CRON" || block lock_patch_failed
grep -q "XYPTDQ_PUBLISH_SOURCE=$STABLE_QUEUE" "$PUBLISHER_CRON" || block source_not_verified
grep -q "XYPTDQ_PUBLISH_STATE=$ORDINARY_STATE" "$PUBLISHER_CRON" || block state_not_verified
grep -q "XYPTDQ_PUBLISH_LOCK=$ORDINARY_LOCK" "$PUBLISHER_CRON" || block lock_not_verified

PHASE="verify"
# canary still present after mutations
CANARY_AFTER=$(python3 - "$STABLE_QUEUE" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
for p in root.glob("*.json"):
    try:
        x = json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        continue
    if x.get("source_article_id") == "LCM-ANGLE-0b6f9c192c45dc31":
        print(json.dumps({"present": True, "publication_state": x.get("publication_state"), "publish_at": x.get("publish_at")})); break
else:
    print(json.dumps({"present": False}))
PY
)
echo "$CANARY_AFTER" | grep -q '"present": true' || block canary_lost_after_mutation

PHASE="complete"
STATUS="PASS"
write_result
echo "HOLD_PROMOTION_ISOLATE_PUBLISHER_V1=PASS promotion_cron_held=yes publisher_state_isolated=yes canary=$CANARY_AFTER"
