#!/bin/bash
# Generate or reuse a dedicated server-side SSH key for read-only access to the private article repository.
# The private key never leaves the production host; only the public key and fingerprint are reported.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
KEY_DIR="${XYPTDQ_ARTICLE_REPO_KEY_DIR:-/var/lib/xyptdq-content/intake/credentials}"
KEY_FILE="$KEY_DIR/caipiaowenzhang_readonly_ed25519"
PUB_FILE="$KEY_FILE.pub"
[ -n "$RESULT_FILE" ] || exit 2

mkdir -p "$KEY_DIR"
chmod 0700 "$KEY_DIR"
CREATED=false

if [ -e "$KEY_FILE" ] || [ -e "$PUB_FILE" ]; then
  [ -s "$KEY_FILE" ] && [ -s "$PUB_FILE" ] || {
    python3 - "$RESULT_FILE" <<'PY'
import json,sys
p={'task':'provision_article_repo_readonly_deploy_key_v1','status':'FAIL','phase':'existing_key_incomplete','private_key_exported':False,'cms_write_attempted':False,'cron_mutated':False,'queue_consumed':False,'intake_enabled':False}
with open(sys.argv[1],'w',encoding='utf-8') as f: json.dump(p,f,ensure_ascii=False,indent=2,sort_keys=True); f.write('\n')
PY
    exit 20
  }
else
  command -v ssh-keygen >/dev/null 2>&1 || exit 21
  ssh-keygen -q -t ed25519 -N '' -C 'xyptdq-intake-readonly@laocaimi' -f "$KEY_FILE"
  CREATED=true
fi

chmod 0600 "$KEY_FILE"
chmod 0644 "$PUB_FILE"
PUBLIC_KEY=$(cat "$PUB_FILE")
FINGERPRINT=$(ssh-keygen -lf "$PUB_FILE" -E sha256 | awk '{print $2}')

case "$PUBLIC_KEY" in
  ssh-ed25519\ *) ;;
  *) exit 22 ;;
esac

python3 - "$RESULT_FILE" "$PUBLIC_KEY" "$FINGERPRINT" "$CREATED" "$KEY_FILE" <<'PY'
import json,sys
out,pub,fp,created,key_path=sys.argv[1:]
p={
 'task':'provision_article_repo_readonly_deploy_key_v1','status':'PASS',
 'target_repository':'fdsasaaa/caipiaowenzhang','usage':'read_only_deploy_key_for_xyptdq_inventory_intake',
 'public_key':pub,'fingerprint':fp,'created_new_key':created=='true',
 'private_key_path':key_path,'private_key_exported':False,
 'required_github_setting':'Deploy key with Allow write access disabled',
 'cms_write_attempted':False,'cron_mutated':False,'queue_consumed':False,'intake_enabled':False
}
with open(out,'w',encoding='utf-8') as f: json.dump(p,f,ensure_ascii=False,indent=2,sort_keys=True); f.write('\n')
PY

echo ARTICLE_REPO_READONLY_DEPLOY_KEY=PASS
