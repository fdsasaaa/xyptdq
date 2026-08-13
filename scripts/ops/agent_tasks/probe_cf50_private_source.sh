#!/bin/bash
# Read-only probe for trusted production access to the private article source.
# No website/CMS writes. No credentials or remote stderr are emitted.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
PRODUCTION_REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
ARTICLE_REPO_HTTPS="https://github.com/fdsasaaa/caipiaowenzhang.git"
ARTICLE_REPO_SSH="git@github.com:fdsasaaa/caipiaowenzhang.git"
BATCH_INDEX="articles/batches/CF50-20260813.json"
APPROVED_GLOB="LCM-CREATOR-cf50-20260813-*.json"

[ -n "$RESULT_FILE" ] || { echo "missing XYPTDQ_AGENT_RESULT_FILE" >&2; exit 2; }
[ -d "$PRODUCTION_REPO/.git" ] || { echo "production repo missing" >&2; exit 3; }

TMP_DIR=$(mktemp -d)
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

write_result() {
  local status="$1"
  local mode="$2"
  local source_sha="$3"
  local batch_count="$4"
  local inventory_count="$5"
  local detail="$6"
  python3 - "$RESULT_FILE" "$status" "$mode" "$source_sha" "$batch_count" "$inventory_count" "$detail" <<'PY'
import json, sys
from datetime import datetime, timezone
out, status, mode, source_sha, batch_count, inventory_count, detail = sys.argv[1:]
payload = {
    "task": "cf50_private_source_probe",
    "source_repository": "fdsasaaa/caipiaowenzhang",
    "source_ref": "main",
    "batch_index": "articles/batches/CF50-20260813.json",
    "approved_pattern": "articles/approved/LCM-CREATOR-cf50-20260813-*.json",
    "source_access": status,
    "access_mode": mode or None,
    "source_main_sha": source_sha or None,
    "batch_declared_count": int(batch_count) if batch_count.isdigit() else None,
    "formal_inventory_count": int(inventory_count) if inventory_count.isdigit() else None,
    "batch_inventory_validation": "PASS" if status == "PASS" else "NOT_PROVEN",
    "detail": detail,
    "checked_at": datetime.now(timezone.utc).isoformat(),
    "website_or_cms_write_attempted": False,
    "secrets_disclosed": False,
}
with open(out, "w", encoding="utf-8") as fh:
    json.dump(payload, fh, ensure_ascii=False, indent=2, sort_keys=True)
    fh.write("\n")
PY
}

ACCESS_MODE=""
REMOTE_URL=""

if GIT_TERMINAL_PROMPT=0 git ls-remote "$ARTICLE_REPO_HTTPS" refs/heads/main \
    >"$TMP_DIR/https.out" 2>"$TMP_DIR/https.err"; then
  ACCESS_MODE="https_existing_credentials"
  REMOTE_URL="$ARTICLE_REPO_HTTPS"
elif GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=12 -o StrictHostKeyChecking=accept-new" \
    git ls-remote "$ARTICLE_REPO_SSH" refs/heads/main \
    >"$TMP_DIR/ssh.out" 2>"$TMP_DIR/ssh.err"; then
  ACCESS_MODE="ssh_existing_credentials"
  REMOTE_URL="$ARTICLE_REPO_SSH"
else
  write_result "FAIL" "" "" "" "" "Production host has no non-interactive read access to the private article repository."
  echo "CF50_PRIVATE_SOURCE_PROBE=FAIL" >&2
  exit 20
fi

export GIT_TERMINAL_PROMPT=0
if [ "$ACCESS_MODE" = "ssh_existing_credentials" ]; then
  export GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=12 -o StrictHostKeyChecking=accept-new"
fi

git clone --depth 1 --filter=blob:none --no-checkout "$REMOTE_URL" "$TMP_DIR/article-repo" \
  >"$TMP_DIR/clone.out" 2>"$TMP_DIR/clone.err"

git -C "$TMP_DIR/article-repo" sparse-checkout init --cone \
  >"$TMP_DIR/sparse-init.out" 2>"$TMP_DIR/sparse-init.err"
git -C "$TMP_DIR/article-repo" sparse-checkout set articles/approved articles/batches \
  >"$TMP_DIR/sparse-set.out" 2>"$TMP_DIR/sparse-set.err"
git -C "$TMP_DIR/article-repo" checkout main \
  >"$TMP_DIR/checkout.out" 2>"$TMP_DIR/checkout.err"

SOURCE_SHA=$(git -C "$TMP_DIR/article-repo" rev-parse HEAD)

VALIDATION=$(
python3 - "$TMP_DIR/article-repo/$BATCH_INDEX" "$TMP_DIR/article-repo/articles/approved" <<'PY'
import glob
import json
import os
import sys

index_path, approved_dir = sys.argv[1:]
with open(index_path, "r", encoding="utf-8") as fh:
    batch = json.load(fh)

declared = batch.get("count")
if declared != 50:
    raise SystemExit(f"unexpected batch count: {declared!r}")

files = sorted(glob.glob(os.path.join(
    approved_dir, "LCM-CREATOR-cf50-20260813-*.json"
)))
if len(files) != 50:
    raise SystemExit(f"unexpected formal inventory count: {len(files)}")

expected_ids = [f"LCM-CREATOR-cf50-20260813-{i:03d}" for i in range(1, 51)]
seen_ids = []
for path in files:
    with open(path, "r", encoding="utf-8") as fh:
        pkg = json.load(fh)
    if pkg.get("status") != "approved":
        raise SystemExit(f"non-approved package: {os.path.basename(path)}")
    if pkg.get("site_category_key") != "tzjq":
        raise SystemExit(f"unexpected category: {os.path.basename(path)}")
    article_id = pkg.get("article_id")
    seen_ids.append(article_id)
    if not pkg.get("content_hash"):
        raise SystemExit(f"missing content_hash: {os.path.basename(path)}")

if seen_ids != expected_ids:
    raise SystemExit("article_id sequence does not match CF50-001..050")

print(f"{declared}|{len(files)}")
PY
)

BATCH_COUNT="${VALIDATION%%|*}"
INVENTORY_COUNT="${VALIDATION##*|}"
write_result "PASS" "$ACCESS_MODE" "$SOURCE_SHA" "$BATCH_COUNT" "$INVENTORY_COUNT" \
  "Private source is readable non-interactively and the CF50 formal inventory matches the declared 50-package batch."
echo "CF50_PRIVATE_SOURCE_PROBE=PASS"
