#!/bin/bash
# Prove dedicated read-only SSH transport to caipiaowenzhang/main and run a read-only inventory diff.
# No Draft/CMS/Publisher/cron writes are permitted.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
INTAKE_ROOT="${XYPTDQ_INTAKE_ROOT:-/var/lib/xyptdq-content/intake}"
KEY_FILE="$INTAKE_ROOT/credentials/caipiaowenzhang_readonly_ed25519"
KNOWN_HOSTS="$INTAKE_ROOT/credentials/github_known_hosts"
SOURCE_DIR="$INTAKE_ROOT/source/caipiaowenzhang"
LEDGER="$INTAKE_ROOT/state.json"
REMOTE="git@github.com:fdsasaaa/caipiaowenzhang.git"
EXPECTED_KEY_FP="SHA256:qgkoW70e+CTTmZ+AQOxM/kcpHu5i0WsinMMSXoMKD7E"
EXPECTED_GITHUB_HOST_FP="SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU"
# Official github.com Ed25519 host key from GitHub documentation.
GITHUB_HOST_KEY="github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl"
[ -n "$RESULT_FILE" ] || exit 2

TMP=$(mktemp -d /tmp/xyptdq-intake-ssh-proof.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$INTAKE_ROOT/credentials" "$INTAKE_ROOT/source"
chmod 0700 "$INTAKE_ROOT/credentials"

write_fail() {
  local phase="$1" detail="$2"
  python3 - "$RESULT_FILE" "$phase" "$detail" <<'PY'
import json,sys
out,phase,detail=sys.argv[1:]
p={
 'task':'prove_article_repo_ssh_inventory_v1','status':'FAIL','phase':phase,'detail':detail,
 'target_repository':'fdsasaaa/caipiaowenzhang','source_ref':'main','read_only':True,
 'private_key_exported':False,'cms_write_attempted':False,'draft_write_attempted':False,
 'ledger_write_attempted':False,'publish_at_created':False,'publisher_invoked':False,
 'cron_mutated':False,'queue_consumed':False,'automatic_intake_enabled':False
}
with open(out,'w',encoding='utf-8') as f: json.dump(p,f,ensure_ascii=False,indent=2,sort_keys=True); f.write('\n')
PY
  echo "ARTICLE_REPO_SSH_INVENTORY=FAIL phase=$phase" >&2
  exit 20
}

[ -d "$REPO/.git" ] || write_fail repo_sync "canonical website repo missing"
[ -z "$(git -C "$REPO" status --porcelain)" ] || write_fail repo_sync "canonical website repo dirty"
git -C "$REPO" fetch --prune origin main >/dev/null 2>&1 || write_fail repo_sync "website main fetch failed"
git -C "$REPO" checkout -q main || write_fail repo_sync "website main checkout failed"
git -C "$REPO" reset --hard origin/main >/dev/null || write_fail repo_sync "website main reset failed"
[ -s "$REPO/scripts/content/inventory_diff.py" ] || write_fail preflight "inventory_diff.py missing"
[ -s "$KEY_FILE" ] || write_fail key_preflight "dedicated private key missing"
chmod 0600 "$KEY_FILE"
KEY_FP=$(ssh-keygen -lf "$KEY_FILE" -E sha256 2>/dev/null | awk '{print $2}')
[ "$KEY_FP" = "$EXPECTED_KEY_FP" ] || write_fail key_preflight "dedicated key fingerprint mismatch"

printf '%s\n' "$GITHUB_HOST_KEY" > "$KNOWN_HOSTS"
chmod 0600 "$KNOWN_HOSTS"
HOST_FP=$(printf '%s\n' "$GITHUB_HOST_KEY" | ssh-keygen -lf - -E sha256 2>/dev/null | awk '{print $2}')
[ "$HOST_FP" = "$EXPECTED_GITHUB_HOST_FP" ] || write_fail host_key_preflight "pinned GitHub host key fingerprint mismatch"

export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="ssh -i $KEY_FILE -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$KNOWN_HOSTS -o PasswordAuthentication=no -o KbdInteractiveAuthentication=no"

LS_REMOTE=$(git ls-remote "$REMOTE" refs/heads/main 2>"$TMP/lsremote.err" | awk '$2=="refs/heads/main"{print $1}') || write_fail ssh_ls_remote "git ls-remote failed"
printf '%s' "$LS_REMOTE" | grep -Eq '^[0-9a-f]{40}$' || write_fail ssh_ls_remote "main ref was not returned as a commit SHA"

if [ ! -d "$SOURCE_DIR/.git" ]; then
  rm -rf "$SOURCE_DIR"
  git clone -q --depth=1 --branch main --single-branch "$REMOTE" "$SOURCE_DIR" 2>"$TMP/clone.err" || write_fail ssh_clone "read-only source clone failed"
else
  ORIGIN=$(git -C "$SOURCE_DIR" remote get-url origin 2>/dev/null || true)
  [ "$ORIGIN" = "$REMOTE" ] || write_fail source_cache "existing source cache origin mismatch"
  [ -z "$(git -C "$SOURCE_DIR" status --porcelain)" ] || write_fail source_cache "existing dedicated source cache is dirty"
  git -C "$SOURCE_DIR" fetch -q --prune origin main 2>"$TMP/fetch.err" || write_fail ssh_fetch "source fetch failed"
  git -C "$SOURCE_DIR" checkout -q main || write_fail source_cache "source main checkout failed"
  git -C "$SOURCE_DIR" reset --hard origin/main >/dev/null || write_fail source_cache "source reset to origin/main failed"
fi
SOURCE_HEAD=$(git -C "$SOURCE_DIR" rev-parse HEAD)
ORIGIN_MAIN=$(git -C "$SOURCE_DIR" rev-parse refs/remotes/origin/main)
[ "$SOURCE_HEAD" = "$LS_REMOTE" ] && [ "$ORIGIN_MAIN" = "$LS_REMOTE" ] || write_fail source_sync "source checkout does not match remote main"

python3 "$REPO/scripts/content/inventory_diff.py" \
  --source-repo="$SOURCE_DIR" \
  --website-repo="$REPO" \
  --ledger="$LEDGER" \
  --output="$TMP/inventory.json" 2>"$TMP/inventory.err" || write_fail inventory_diff "inventory_diff.py failed"

python3 - "$TMP/inventory.json" "$RESULT_FILE" "$SOURCE_HEAD" "$KEY_FP" "$HOST_FP" <<'PY'
import json,sys
inv=json.load(open(sys.argv[1],encoding='utf-8'))
out,source_head,key_fp,host_fp=sys.argv[2:]
expected={
 'A_upstream_official_ready':45,
 'website_ingress_known':12,
 'ledger_known':0,
 'new_draft_candidates':33,
 'cf50_frozen_final5_count':5,
}
errors=[]
for k,v in expected.items():
    if inv.get(k)!=v: errors.append(f'{k} expected {v} got {inv.get(k)!r}')
if inv.get('cf50_final5_release_authorized') is not False:
    errors.append('cf50 final five unexpectedly authorized')
frozen=set(inv.get('cf50_frozen_final5_article_ids') or [])
candidate_ids=list(inv.get('candidate_revision_ids') or [])
if any(str(x).split(':',1)[0] in frozen for x in candidate_ids):
    errors.append('frozen final-five revision leaked into Draft candidates')
if inv.get('source_commit') != source_head:
    errors.append('inventory source_commit does not match proven SSH main HEAD')
status='PASS' if not errors else 'FAIL'
p={
 'task':'prove_article_repo_ssh_inventory_v1','status':status,
 'phase':'complete' if not errors else 'inventory_assertions',
 'detail':'dedicated read-only SSH transport and inventory dry-run both passed' if not errors else '; '.join(errors),
 'target_repository':'fdsasaaa/caipiaowenzhang','source_ref':'main','source_commit':source_head,
 'ssh_main_read':'PASS','source_checkout_synced':'PASS','inventory_diff_status':inv.get('status'),
 'A_upstream_official_ready':inv.get('A_upstream_official_ready'),
 'website_ingress_known':inv.get('website_ingress_known'),'ledger_known':inv.get('ledger_known'),
 'new_draft_candidates':inv.get('new_draft_candidates'),
 'candidate_revision_ids':candidate_ids,
 'cf50_final5_release_authorized':inv.get('cf50_final5_release_authorized'),
 'cf50_frozen_final5_count':inv.get('cf50_frozen_final5_count'),
 'cf50_frozen_final5_article_ids':sorted(frozen),
 'deploy_key_fingerprint':key_fp,'github_host_key_fingerprint':host_fp,
 'host_key_validation':'pinned_official_github_ed25519',
 'read_only':True,'private_key_exported':False,'cms_write_attempted':False,
 'draft_write_attempted':False,'ledger_write_attempted':False,'publish_at_created':False,
 'publisher_invoked':False,'cron_mutated':False,'queue_consumed':False,
 'automatic_intake_enabled':False
}
with open(out,'w',encoding='utf-8') as f: json.dump(p,f,ensure_ascii=False,indent=2,sort_keys=True); f.write('\n')
if errors: raise SystemExit(20)
PY

echo ARTICLE_REPO_SSH_INVENTORY=PASS
