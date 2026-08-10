#!/bin/bash
# Read-only/local-Git diagnostic for Publisher V6. No deploy and no CMS writes.
set -Eeuo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
CANONICAL="https://www.laocaimi.org"
EXPECTED_FRAME_LOCK_HEX="436f646549676e697465723732"
RUN_ID="$(date +%Y%m%d_%H%M%S)"
LOCAL_BRANCH="agent/local-v6-diagnose-${RUN_ID}"
CATEGORY_JSON="/tmp/xyptdq-v6-diagnose-${RUN_ID}.json"
PHASE="init"

[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3

write_payload() {
  local status="$1"
  local rc="$2"
  local phase="$3"
  python3 - "$RESULT_FILE" "$status" "$rc" "$phase" <<'PY'
import json, re, sys
out, status, rc, phase = sys.argv[1:]
phase = re.sub(r'[^A-Za-z0-9_.:-]', '', phase)[:120]
with open(out, 'w', encoding='utf-8') as fh:
    json.dump({
        'task': 'publisher_v6_diagnose',
        'diagnostic': status,
        'exit_code': int(rc),
        'phase': phase,
        'secrets_disclosed': False,
    }, fh, ensure_ascii=False, indent=2, sort_keys=True)
    fh.write('\n')
PY
}

cleanup() {
  rm -f "$CATEGORY_JSON" >/dev/null 2>&1 || true
  if [ -d "$REPO/.git" ]; then
    cd "$REPO" || true
    git checkout -f main >/dev/null 2>&1 || true
    git reset --hard origin/main >/dev/null 2>&1 || true
    git branch -D "$LOCAL_BRANCH" >/dev/null 2>&1 || true
  fi
}

on_err() {
  local rc=$?
  trap - ERR
  write_payload "FAIL" "$rc" "$PHASE"
  cleanup
  exit "$rc"
}
trap on_err ERR
trap cleanup EXIT

cd "$REPO"

PHASE="repo_clean"
[ -z "$(git status --porcelain)" ]

PHASE="repo_sync"
git fetch --prune origin
git checkout main >/dev/null 2>&1
git reset --hard origin/main >/dev/null

PHASE="baseline_http"
for path in / /robots.txt /sitemap.xml; do
  code=$(curl -sk --max-time 30 -o /dev/null -w '%{http_code}' "$CANONICAL$path")
  [ "$code" = 200 ]
done

PHASE="cache_factory"
CACHE_SRC="$WEBROOT/dayrui/CodeIgniter72/System/Cache"
[ -f "$CACHE_SRC/CacheFactory.php" ]

PHASE="frame_lock"
mapfile -t FRAME_LOCKS < <(find "$WEBROOT" -type f -iname 'frame.lock' -print)
[ "${#FRAME_LOCKS[@]}" -eq 1 ]
FRAME_LOCK="${FRAME_LOCKS[0]}"
FRAME_REL="${FRAME_LOCK#"$WEBROOT/"}"
FRAME_HEX=$(od -An -tx1 -v "$FRAME_LOCK" | tr -d ' \n')
[ "$FRAME_HEX" = "$EXPECTED_FRAME_LOCK_HEX" ]

PHASE="local_branch"
git checkout -b "$LOCAL_BRANCH" origin/main >/dev/null
git config user.name 'xyptdq-server-agent'
git config user.email 'xyptdq-agent@localhost'

PHASE="copy_cache"
mkdir -p "$REPO/site/dayrui/CodeIgniter72/System/Cache"
rsync -a --delete "$CACHE_SRC/" "$REPO/site/dayrui/CodeIgniter72/System/Cache/"
mkdir -p "$REPO/site/$(dirname "$FRAME_REL")"
cp -p "$FRAME_LOCK" "$REPO/site/$FRAME_REL"

PHASE="git_add_cache"
git add site/dayrui/CodeIgniter72/System/Cache
git add "site/$FRAME_REL"
git diff --cached --check

PHASE="git_commit_local"
if ! git diff --cached --quiet; then
  git commit -m 'Local Publisher V6 diagnostic recovery snapshot' >/dev/null
fi

PHASE="category_probe"
php scripts/content/category_probe.php --output="$CATEGORY_JSON" >/dev/null
php -r '$x=json_decode(file_get_contents($argv[1]),true); foreach(($x["categories"]??[]) as $c){ if((int)($c["id"]??0)===7) exit(0); } exit(1);' "$CATEGORY_JSON"

PHASE="target_preflight"
DRY_OUTPUT=$(php scripts/content/publisher_smoke.php --article=content/smoke/ffc-betting-basics-risk-v1.json 2>&1)
printf '%s\n' "$DRY_OUTPUT" | grep -Fq 'TARGET_PREFLIGHT PASS'
printf '%s\n' "$DRY_OUTPUT" | grep -Fq 'DRY-RUN ONLY; no database write attempted.'

PHASE="complete"
write_payload "PASS" 0 "$PHASE"
echo "PUBLISHER_V6_DIAGNOSE=PASS"
