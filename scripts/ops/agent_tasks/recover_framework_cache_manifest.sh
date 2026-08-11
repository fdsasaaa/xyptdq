#!/bin/bash
# Read-only manifest of the production CodeIgniter72 Cache source and frame.lock.
set -euo pipefail
umask 077
RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
CACHE="$WEBROOT/dayrui/CodeIgniter72/System/Cache"
EXPECTED_FRAME_LOCK_HEX="436f646549676e697465723732"
[ -n "$RESULT_FILE" ] || exit 2
[ -d "$CACHE" ] || exit 3
mapfile -t LOCKS < <(find "$WEBROOT/dayrui" -type f -iname 'frame.lock' -print 2>/dev/null | sort)
[ "${#LOCKS[@]}" -eq 1 ] || exit 4
FRAME="${LOCKS[0]}"
HEX=$(od -An -tx1 -v "$FRAME" | tr -d ' \n')
[ "$HEX" = "$EXPECTED_FRAME_LOCK_HEX" ] || exit 5
python3 - "$CACHE" "$WEBROOT" "$FRAME" "$RESULT_FILE" <<'PY'
import hashlib,json,pathlib,sys
cache=pathlib.Path(sys.argv[1]); web=pathlib.Path(sys.argv[2]); frame=pathlib.Path(sys.argv[3]); out=pathlib.Path(sys.argv[4])
files=[]
total=0
for p in sorted(cache.rglob('*')):
    if not p.is_file(): continue
    data=p.read_bytes(); total+=len(data)
    files.append({"path":str(p.relative_to(web)),"bytes":len(data),"sha256":hashlib.sha256(data).hexdigest()})
fdata=frame.read_bytes()
payload={
 "task":"recover_framework_cache_manifest",
 "manifest_status":"PASS",
 "blocking_item":"NONE",
 "cache_file_count":len(files),
 "cache_total_bytes":total,
 "files":files,
 "frame_lock":{"path":str(frame.relative_to(web)),"bytes":len(fdata),"sha256":hashlib.sha256(fdata).hexdigest(),"exact_codeigniter72":True},
 "secrets_disclosed":False,
}
out.write_text(json.dumps(payload,ensure_ascii=False,indent=2,sort_keys=True)+'\n',encoding='utf-8')
PY
echo "FRAMEWORK_CACHE_MANIFEST=PASS"
