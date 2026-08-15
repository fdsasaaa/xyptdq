#!/bin/bash
# Read-only capability probe: can the production automation host read the private article repository main ref?
set -uo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
SOURCE_REPO="https://github.com/fdsasaaa/caipiaowenzhang.git"
[ -n "$RESULT_FILE" ] || exit 2

TMP=$(mktemp -d /tmp/xyptdq-article-transport-probe.XXXXXX) || exit 3
trap 'rm -rf "$TMP"' EXIT

GIT_TERMINAL_PROMPT=0 timeout 30 git ls-remote "$SOURCE_REPO" refs/heads/main >"$TMP/out" 2>"$TMP/err"
RC=$?
SHA=""
if [ "$RC" -eq 0 ]; then
  SHA=$(awk 'NR==1{print $1}' "$TMP/out")
fi

python3 - "$RESULT_FILE" "$RC" "$SHA" <<'PY'
import json, re, sys
out, rc, sha = sys.argv[1:]
valid = bool(re.fullmatch(r'[0-9a-f]{40}', sha))
payload={
  'task':'probe_article_repo_transport_v1',
  'status':'PASS',
  'read_only':True,
  'source_repository':'fdsasaaa/caipiaowenzhang',
  'source_ref':'main',
  'git_ls_remote_exit_code':int(rc),
  'private_repo_read_access':bool(int(rc)==0 and valid),
  'resolved_main_sha':sha if valid else None,
  'credentials_printed':False,
  'cms_write_attempted':False,
  'cron_mutated':False,
  'queue_consumed':False,
  'recommendation':'server_side_inventory_intake_possible' if int(rc)==0 and valid else 'trusted_private_repo_credential_still_required',
}
with open(out,'w',encoding='utf-8') as fh:
    json.dump(payload,fh,ensure_ascii=False,indent=2,sort_keys=True)
    fh.write('\n')
PY

echo ARTICLE_REPO_TRANSPORT_PROBE_V1=PASS
exit 0
