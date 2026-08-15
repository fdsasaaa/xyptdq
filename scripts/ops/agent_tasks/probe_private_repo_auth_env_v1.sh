#!/bin/bash
# Read-only authentication capability probe. Never emits credential values.
set -euo pipefail
umask 077
RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
[ -n "$RESULT_FILE" ] || exit 2
TMP=$(mktemp -d /tmp/xyptdq-authprobe.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

CANDIDATES=(GITHUB_TOKEN GH_TOKEN XYPTDQ_GITHUB_TOKEN XYPTDQ_AGENT_GITHUB_TOKEN GITHUB_API_TOKEN GH_PAT)
printf '[]\n' > "$TMP/results.json"
for NAME in "${CANDIDATES[@]}"; do
  VALUE="${!NAME:-}"
  PRESENT=false
  CODE=0
  if [ -n "$VALUE" ]; then
    PRESENT=true
    set +e
    CODE=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 \
      -H 'Accept: application/vnd.github+json' \
      -H "Authorization: Bearer $VALUE" \
      -H 'X-GitHub-Api-Version: 2022-11-28' \
      'https://api.github.com/repos/fdsasaaa/caipiaowenzhang')
    RC=$?
    set -e
    if [ "$RC" -ne 0 ]; then CODE=0; fi
  fi
  python3 - "$TMP/results.json" "$NAME" "$PRESENT" "$CODE" <<'PY'
import json,sys
p,name,present,code=sys.argv[1:]
rows=json.load(open(p,encoding='utf-8'))
rows.append({'name':name,'present':present=='true','private_repo_api_http':int(code)})
with open(p,'w',encoding='utf-8') as f: json.dump(rows,f,indent=2,sort_keys=True); f.write('\n')
PY
done

HELPER=$(git config --global --get credential.helper 2>/dev/null || true)
python3 - "$RESULT_FILE" "$TMP/results.json" "$HELPER" <<'PY'
import json,sys
out,rows_path,helper=sys.argv[1:]
rows=json.load(open(rows_path,encoding='utf-8'))
usable=[r['name'] for r in rows if r['present'] and r['private_repo_api_http']==200]
p={
 'task':'probe_private_repo_auth_env_v1','status':'PASS','read_only':True,
 'credential_values_printed':False,'candidate_environment_results':rows,
 'usable_private_repo_token_environment_names':usable,
 'git_global_credential_helper_configured':bool(helper.strip()),
 'private_repo_authenticated_read_available':bool(usable),
 'recommendation':'reuse_existing_secret_environment_for_minimum_read_only_transport_after_scope_review' if usable else 'provision_dedicated_read_only_private_repo_credential',
 'cms_write_attempted':False,'cron_mutated':False,'queue_consumed':False
}
with open(out,'w',encoding='utf-8') as f: json.dump(p,f,ensure_ascii=False,indent=2,sort_keys=True); f.write('\n')
PY

echo PRIVATE_REPO_AUTH_ENV_PROBE=PASS
