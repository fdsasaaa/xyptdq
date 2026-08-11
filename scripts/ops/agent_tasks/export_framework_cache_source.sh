#!/bin/bash
# Export only the known production CodeIgniter72 Cache source as base64 in two
# bounded, sanitized Server Bridge payloads so GitHub can re-version the exact
# production framework bytes. No configuration/credential paths are readable.
set -euo pipefail
umask 077
RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
JOB_ID="${XYPTDQ_AGENT_JOB_ID:-}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
BASE="$WEBROOT/dayrui/CodeIgniter72/System/Cache"
[ -n "$RESULT_FILE" ] || exit 2
[ -d "$BASE" ] || exit 3

case "$JOB_ID" in
  export-framework-cache-part-a-20260811-01)
    FILES=(
      CacheFactory.php
      CacheInterface.php
      Exceptions/CacheException.php
      Exceptions/ExceptionInterface.php
      Handlers/BaseHandler.php
      Handlers/DummyHandler.php
      Handlers/FileHandler.php
    )
    PART="A"
    ;;
  export-framework-cache-part-b-20260811-01)
    FILES=(
      Handlers/MemcachedHandler.php
      Handlers/PredisHandler.php
      Handlers/RedisHandler.php
      Handlers/WincacheHandler.php
    )
    PART="B"
    ;;
  *) exit 4 ;;
esac

python3 - "$BASE" "$WEBROOT" "$RESULT_FILE" "$PART" "${FILES[@]}" <<'PY'
import base64,hashlib,json,os,pathlib,sys
base=pathlib.Path(sys.argv[1]).resolve(); web=pathlib.Path(sys.argv[2]).resolve(); out=pathlib.Path(sys.argv[3]); part=sys.argv[4]
rels=sys.argv[5:]
items=[]; total=0
for rel in rels:
    p=(base/rel).resolve()
    if base not in p.parents or not p.is_file():
        raise SystemExit(10)
    b=p.read_bytes(); total+=len(b)
    items.append({
        'path':str(p.relative_to(web)),
        'bytes':len(b),
        'sha256':hashlib.sha256(b).hexdigest(),
        'content_base64':base64.b64encode(b).decode('ascii'),
    })
locks=[]
for root,dirs,files in os.walk(web):
    relroot=os.path.relpath(root,web)
    if relroot.split(os.sep,1)[0] in {'cache','uploadfile','uploads'}:
        dirs[:] = []
        continue
    for name in files:
        if name.lower()!='frame.lock': continue
        p=pathlib.Path(root)/name
        b=p.read_bytes()
        locks.append({
            'path':str(p.relative_to(web)),
            'bytes':len(b),
            'sha256':hashlib.sha256(b).hexdigest(),
            'content_base64':base64.b64encode(b).decode('ascii') if len(b)<=256 else '',
            'exact_codeigniter72':b.hex()=='436f646549676e697465723732',
        })
payload={
 'task':'export_framework_cache_source','export_status':'PASS','blocking_item':'NONE','part':part,
 'file_count':len(items),'total_bytes':total,'files':items,
 'frame_lock_candidates':locks,'secrets_disclosed':False,
}
out.write_text(json.dumps(payload,ensure_ascii=False,indent=2,sort_keys=True)+'\n',encoding='utf-8')
PY

echo "FRAMEWORK_CACHE_EXPORT=PASS part=$PART"
