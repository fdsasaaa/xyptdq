#!/bin/bash
# Deterministic v3 wrapper around the already-reviewed v2 full verification/rollback deployer.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
BASE="$REPO/scripts/ops/agent_tasks/deploy_platform_duplicate_description_hash_fallback_v2.sh"
BASE_SHA="6a09be7d805542a0520191e4339cee3163edb67b836f34ab6230bd8f95f4f343"
OLD_TARGET="3896887d20bb1604c577c6b57c26d51201600e22"
NEW_TARGET="ed01a5ed9dc3de59bebf9684b1c5bd9904316d99"
TMP="$(mktemp /tmp/xyptdq-meta-v3.XXXXXX.sh)"
trap 'rm -f "$TMP"' EXIT

write_blocked(){
  local item="$1"
  if [ -n "$RESULT_FILE" ]; then
    python3 - "$RESULT_FILE" "$item" <<'PY'
import json,sys
out,item=sys.argv[1:]
p={"task":"deploy_news_duplicate_description_hash_fallback_v3","deployment_status":"BLOCKED","phase":"wrapper_verify","deploy":"NO","rollback":"NO","deploy_error_class":item,"blocking_item":item,"article_publishing_attempted":False,"secrets_disclosed":False}
with open(out,"w",encoding="utf-8") as f: json.dump(p,f,ensure_ascii=False,indent=2,sort_keys=True); f.write("\n")
PY
  fi
  echo "[news-meta-v3] BLOCKED: $item" >&2
  exit 1
}

[ -n "$RESULT_FILE" ] || exit 2
[ -f "$BASE" ] || write_blocked base_script_missing
[ "$(sha256sum "$BASE" | awk '{print $1}')" = "$BASE_SHA" ] || write_blocked base_script_sha_mismatch

if ! python3 - "$BASE" "$TMP" "$OLD_TARGET" "$NEW_TARGET" <<'PY'
from pathlib import Path
import sys
src,out,old_target,new_target=sys.argv[1:]
s=Path(src).read_text(encoding='utf-8')
old_target_line=f'TARGET_SHA="{old_target}"'
new_target_line=f'TARGET_SHA="{new_target}"'
old_guard='\\$xyptdq_module === \'xm\''
new_guard='\\$xyptdq_module === \'news\''
if s.count(old_target_line)!=1:
    raise SystemExit('target replacement cardinality mismatch')
if s.count(old_guard)!=1:
    raise SystemExit('module guard replacement cardinality mismatch')
s=s.replace(old_target_line,new_target_line,1).replace(old_guard,new_guard,1)
s=s.replace('deploy_platform_duplicate_description_hash_fallback_v2','deploy_news_duplicate_description_hash_fallback_v3')
Path(out).write_text(s,encoding='utf-8')
PY
then
  write_blocked deterministic_transform_failed
fi

grep -Fq "TARGET_SHA=\"$NEW_TARGET\"" "$TMP" || write_blocked transformed_target_missing
grep -Fq "\$xyptdq_module === 'news'" "$TMP" || write_blocked transformed_news_guard_missing
if grep -Fq "\$xyptdq_module === 'xm'" "$TMP"; then write_blocked transformed_xm_guard_persisted; fi
chmod 700 "$TMP"
exec bash "$TMP"
