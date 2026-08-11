#!/bin/bash
# Read-only production framework manifest. Never emits file contents or secrets.
set -euo pipefail
umask 077
RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
CACHE="$WEBROOT/dayrui/CodeIgniter72/System/Cache"
EXPECTED_HEX="436f646549676e697465723732"
[ -n "$RESULT_FILE" ] || exit 2
[ -d "$CACHE" ] || exit 3
python3 - "$CACHE" "$WEBROOT" "$RESULT_FILE" "$EXPECTED_HEX" <<'PY'
import hashlib,json,pathlib,sys
cache=pathlib.Path(sys.argv[1]); web=pathlib.Path(sys.argv[2]); out=pathlib.Path(sys.argv[3]); expected=sys.argv[4]
files=[]; total=0
for p in sorted(cache.rglob('*')):
    if p.is_file():
        b=p.read_bytes(); total+=len(b)
        files.append({'path':str(p.relative_to(web)),'bytes':len(b),'sha256':hashlib.sha256(b).hexdigest()})
locks=[]
for p in sorted(web.rglob('frame.lock')):
    try:
        rel=str(p.relative_to(web))
        if rel.startswith(('cache/','uploadfile/','uploads/')): continue
        b=p.read_bytes()
        locks.append({'path':rel,'bytes':len(b),'sha256':hashlib.sha256(b).hexdigest(),'exact_codeigniter72':b.hex()==expected})
    except Exception:
        pass
payload={
 'task':'recover_framework_manifest_v2','manifest_status':'PASS','blocking_item':'NONE',
 'cache_file_count':len(files),'cache_total_bytes':total,'files':files,
 'frame_lock_count':len(locks),'frame_locks':locks,'secrets_disclosed':False,
}
out.write_text(json.dumps(payload,ensure_ascii=False,indent=2,sort_keys=True)+'\n',encoding='utf-8')
PY
echo FRAMEWORK_MANIFEST_V2=PASS
