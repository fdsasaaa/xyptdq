#!/bin/bash
# Rebase only the nine remaining isolated CF50 Wave1 publish_at values by one editorial slot after the 021 pause.
# Requires publication policy to remain disabled. Does not publish, alter CMS, cron, article content, identity, or order.
set -euo pipefail
umask 077
RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
ROOT="/var/lib/xyptdq-content/CF50-20260813-wave1/scheduled"
STATE="/var/lib/xyptdq-publisher/CF50-20260813-wave1/state.json"
POLICY="$REPO/config/content_publication_policy.json"
[ -n "$RESULT_FILE" ] || exit 2
[ -d "$ROOT" ] || exit 3
[ -s "$STATE" ] || exit 4
[ -s "$POLICY" ] || exit 5

TMP=$(mktemp -d /tmp/xyptdq-wave1-rebase.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

POLICY_OK=$(python3 - "$POLICY" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8'))
print('yes' if x.get('publishing_enabled') is False and '021' in str(x.get('mode') or '') else 'no')
PY
)
[ "$POLICY_OK" = yes ] || {
  python3 - "$RESULT_FILE" <<'PY'
import json,sys
p={'task':'rebase_cf50_wave1_remaining_schedule_v1','status':'FAIL','phase':'policy_preflight','detail':'publication policy is not paused on the 021 gate','cms_write_attempted':False,'cron_mutated':False,'queue_consumed':False,'publication_attempted':False,'runtime_mutated':False,'rollback_performed':False}
open(sys.argv[1],'w',encoding='utf-8').write(json.dumps(p,ensure_ascii=False,indent=2,sort_keys=True)+'\n')
PY
  exit 20
}

python3 - "$ROOT" "$STATE" "$TMP" "$RESULT_FILE" <<'PY'
import json,os,pathlib,shutil,sys,tempfile
root=pathlib.Path(sys.argv[1]); state_path=pathlib.Path(sys.argv[2]); tmp=pathlib.Path(sys.argv[3]); result=pathlib.Path(sys.argv[4])
expected=[
 ('LCM-CREATOR-cf50-20260813-031','2026-08-15T19:00:00+08:00','2026-08-16T10:00:00+08:00'),
 ('LCM-CREATOR-cf50-20260813-041','2026-08-16T10:00:00+08:00','2026-08-16T19:00:00+08:00'),
 ('LCM-CREATOR-cf50-20260813-046','2026-08-16T19:00:00+08:00','2026-08-17T10:00:00+08:00'),
 ('LCM-CREATOR-cf50-20260813-002','2026-08-17T10:00:00+08:00','2026-08-17T19:00:00+08:00'),
 ('LCM-CREATOR-cf50-20260813-012','2026-08-17T19:00:00+08:00','2026-08-18T10:00:00+08:00'),
 ('LCM-CREATOR-cf50-20260813-022','2026-08-18T10:00:00+08:00','2026-08-18T19:00:00+08:00'),
 ('LCM-CREATOR-cf50-20260813-032','2026-08-18T19:00:00+08:00','2026-08-19T10:00:00+08:00'),
 ('LCM-CREATOR-cf50-20260813-037','2026-08-19T10:00:00+08:00','2026-08-19T19:00:00+08:00'),
 ('LCM-CREATOR-cf50-20260813-049','2026-08-19T19:00:00+08:00','2026-08-20T10:00:00+08:00'),
]
state=json.loads(state_path.read_text(encoding='utf-8')); states=state.get('articles') or {}
files={}
before=[]
for aid,old,new in expected:
    p=root/f'{aid}.json'
    if not p.is_file(): raise RuntimeError(f'missing runtime file: {p.name}')
    x=json.loads(p.read_text(encoding='utf-8'))
    key=str(x.get('article_key') or '')
    if str(x.get('source_article_id') or x.get('article_id') or '') != aid: raise RuntimeError(f'article identity mismatch: {aid}')
    if str(x.get('source_revision_id') or '') != aid+':public-r1': raise RuntimeError(f'revision mismatch: {aid}')
    if str(x.get('publish_at') or '') != old: raise RuntimeError(f'publish_at precondition mismatch: {aid}')
    st=states.get(key) or {}
    if st.get('status') != 'scheduled' or st.get('cms_id') not in (None,''): raise RuntimeError(f'runtime state is not clean scheduled: {aid}')
    files[aid]=(p,x,new)
    before.append({'article_id':aid,'article_key':key,'old_publish_at':old,'new_publish_at':new,'runtime_status':'scheduled'})
if sum(1 for e in states.values() if (e or {}).get('status')=='published') != 2: raise RuntimeError('expected exactly two published Wave1 entries')
if sum(1 for e in states.values() if (e or {}).get('status')=='scheduled') != 9: raise RuntimeError('expected exactly nine scheduled Wave1 entries')
backup=tmp/'backup'; backup.mkdir()
for aid,(p,x,new) in files.items(): shutil.copy2(p,backup/p.name)
mutated=[]
try:
    for aid,(p,x,new) in files.items():
        x['publish_at']=new
        fd,name=tempfile.mkstemp(prefix=p.name+'.tmp.',dir=str(p.parent)); os.close(fd)
        tp=pathlib.Path(name)
        try:
            tp.write_text(json.dumps(x,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
            os.chmod(tp,0o640)
            os.replace(tp,p)
        finally:
            if tp.exists(): tp.unlink()
        mutated.append(aid)
    after=[]
    for aid,old,new in expected:
        p=root/f'{aid}.json'; x=json.loads(p.read_text(encoding='utf-8'))
        if str(x.get('publish_at') or '') != new: raise RuntimeError(f'post-write publish_at mismatch: {aid}')
        after.append({'article_id':aid,'publish_at':new})
    payload={'task':'rebase_cf50_wave1_remaining_schedule_v1','status':'PASS','phase':'complete','detail':'nine remaining Wave1 items shifted exactly one 10:00/19:00 editorial slot after the 021 pause','before':before,'after':after,'first_remaining_article_id':expected[0][0],'first_remaining_publish_at':expected[0][2],'last_remaining_article_id':expected[-1][0],'last_remaining_publish_at':expected[-1][2],'published_count':2,'scheduled_count':9,'cms_write_attempted':False,'cron_mutated':False,'queue_consumed':False,'publication_attempted':False,'publication_policy_mutated':False,'runtime_mutated':True,'rollback_performed':False,'article_content_mutated':False,'article_identity_mutated':False,'order_mutated':False}
except Exception as exc:
    for b in backup.glob('*.json'): shutil.copy2(b,root/b.name)
    payload={'task':'rebase_cf50_wave1_remaining_schedule_v1','status':'FAIL','phase':'write_or_verify','detail':str(exc),'cms_write_attempted':False,'cron_mutated':False,'queue_consumed':False,'publication_attempted':False,'publication_policy_mutated':False,'runtime_mutated':bool(mutated),'rollback_performed':True,'mutated_before_rollback':mutated}
result.write_text(json.dumps(payload,ensure_ascii=False,indent=2,sort_keys=True)+'\n',encoding='utf-8')
if payload['status']!='PASS': raise SystemExit(20)
PY

echo CF50_WAVE1_REMAINING_SCHEDULE_REBASE=PASS
