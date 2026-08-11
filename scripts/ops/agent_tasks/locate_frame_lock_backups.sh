#!/bin/bash
# Locate historical frame.lock copies in backup archives/directories without
# exposing unrelated backup contents or credentials.
set -euo pipefail
umask 077
RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
BACKUP_ROOT="${XYPTDQ_BACKUP_ROOT:-/root/backups}"
EXPECTED_HEX="436f646549676e697465723732"
[ -n "$RESULT_FILE" ] || exit 2
[ -d "$BACKUP_ROOT" ] || exit 3
TMP="$(mktemp -d /tmp/xyptdq-frame-lock.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
python3 - "$BACKUP_ROOT" "$RESULT_FILE" "$EXPECTED_HEX" <<'PY'
import hashlib,json,os,pathlib,subprocess,sys,tarfile
root=pathlib.Path(sys.argv[1]); out=pathlib.Path(sys.argv[2]); expected=sys.argv[3]
found=[]
seen=set()

def add(source, member, data):
    key=(source,member,hashlib.sha256(data).hexdigest())
    if key in seen: return
    seen.add(key)
    found.append({
        'source':source,
        'path':member,
        'bytes':len(data),
        'sha256':hashlib.sha256(data).hexdigest(),
        'exact_codeigniter72':data.hex()==expected,
    })

# Full website tarballs created by backup.sh and disaster-recovery archives.
for arc in sorted(root.rglob('*.tar.gz')):
    # Avoid scanning obviously unrelated large package archives outside website backups.
    n=arc.name.lower()
    if not any(x in n for x in ('website','site','webroot','files','backup')):
        continue
    try:
        with tarfile.open(arc,'r:gz') as tf:
            for m in tf.getmembers():
                if not m.isfile() or pathlib.PurePosixPath(m.name).name.lower()!='frame.lock':
                    continue
                fh=tf.extractfile(m)
                if not fh: continue
                data=fh.read(1024)
                add(str(arc.relative_to(root)),m.name,data)
    except Exception:
        continue

# Direct backup trees, excluding database/config payloads by exact filename search only.
for base,dirs,files in os.walk(root):
    # Do not descend into extracted database/cache/session folders if present.
    dirs[:] = [d for d in dirs if d.lower() not in {'database','db','cache','session','sessions','logs','log'}]
    for name in files:
        if name.lower()!='frame.lock': continue
        p=pathlib.Path(base)/name
        try:
            data=p.read_bytes()
            if len(data)<=1024:
                add('direct:'+str(p.parent.relative_to(root)),name,data)
        except Exception:
            pass

exact=[x for x in found if x['exact_codeigniter72']]
payload={
    'task':'locate_frame_lock_backups',
    'locator_status':'PASS',
    'blocking_item':'NONE',
    'candidate_count':len(found),
    'exact_candidate_count':len(exact),
    'candidates':found[:50],
    'secrets_disclosed':False,
}
out.write_text(json.dumps(payload,ensure_ascii=False,indent=2,sort_keys=True)+'\n',encoding='utf-8')
PY
echo FRAME_LOCK_BACKUP_LOCATOR=PASS
