#!/bin/bash
# Read-only private source access probe. Records no credential material and never mutates either repository.
set -uo pipefail
umask 077
RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
SOURCE_REPO="https://github.com/fdsasaaa/caipiaowenzhang.git"
[ -n "$RESULT_FILE" ] || exit 2
TMP=$(mktemp -d /tmp/xyptdq-article-transport-v2.XXXXXX) || exit 3
trap 'rm -rf "$TMP"' EXIT

GIT_BIN="$(command -v git 2>/dev/null || true)"
RC=127
SHA=""
if [ -n "$GIT_BIN" ]; then
  GIT_TERMINAL_PROMPT=0 git ls-remote "$SOURCE_REPO" refs/heads/main >"$TMP/out" 2>"$TMP/err"
  RC=$?
  if [ "$RC" -eq 0 ]; then
    SHA=$(awk 'NR==1{print $1}' "$TMP/out")
  fi
fi

python3 - "$RESULT_FILE" "$RC" "$SHA" "$GIT_BIN" <<'PY'
import json,re,sys
out,rc,sha,git_bin=sys.argv[1:]
valid=bool(re.fullmatch(r'[0-9a-f]{40}',sha))
access=int(rc)==0 and valid
p={
 'task':'probe_article_repo_transport_v2','status':'PASS','read_only':True,
 'source_repository':'fdsasaaa/caipiaowenzhang','source_ref':'main',
 'git_bin':git_bin or None,'git_ls_remote_exit_code':int(rc),
 'private_repo_read_access':access,'resolved_main_sha':sha if valid else None,
 'credentials_printed':False,'cms_write_attempted':False,'cron_mutated':False,'queue_consumed':False,
 'recommendation':'server_side_inventory_intake_possible' if access else 'trusted_private_repo_credential_required_before_automatic_intake'
}
with open(out,'w',encoding='utf-8') as f:
 json.dump(p,f,ensure_ascii=False,indent=2,sort_keys=True); f.write('\n')
PY
exit 0
