#!/bin/bash
# Read-only snapshot of remaining CF50 Wave1 runtime schedule after the 021 pause.
set -euo pipefail
umask 077
RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
ROOT="/var/lib/xyptdq-content/CF50-20260813-wave1/scheduled"
STATE="/var/lib/xyptdq-publisher/CF50-20260813-wave1/state.json"
[ -n "$RESULT_FILE" ] || exit 2
[ -d "$ROOT" ] || exit 3
[ -s "$STATE" ] || exit 4

python3 - "$ROOT" "$STATE" "$RESULT_FILE" <<'PY'
import datetime,json,pathlib,sys
root=pathlib.Path(sys.argv[1]); state_path=pathlib.Path(sys.argv[2]); out=pathlib.Path(sys.argv[3])
state=json.loads(state_path.read_text(encoding='utf-8'))
articles_state=state.get('articles') or {}
rows=[]
for path in sorted(root.glob('*.json')):
    data=json.loads(path.read_text(encoding='utf-8'))
    key=str(data.get('article_key') or '')
    e=articles_state.get(key) or {}
    article_id=str(data.get('source_article_id') or data.get('article_id') or '')
    publish_at=str(data.get('publish_at') or '')
    rows.append({
        'article_id':article_id,
        'article_key':key,
        'source_revision_id':data.get('source_revision_id'),
        'publish_at':publish_at,
        'runtime_status':e.get('status'),
        'cms_id':e.get('cms_id'),
        'published_at':e.get('published_at'),
        'retry_count':e.get('retry_count'),
        'last_error':e.get('last_error'),
        'file':path.name,
    })

def parse_iso(v):
    if not v: return None
    try: return datetime.datetime.fromisoformat(v.replace('Z','+00:00'))
    except Exception: return None
now=datetime.datetime.now(datetime.timezone.utc)
remaining=[r for r in rows if r['runtime_status']!='published']
remaining.sort(key=lambda r: (parse_iso(r['publish_at']) or datetime.datetime.max.replace(tzinfo=datetime.timezone.utc), r['article_id']))
for r in remaining:
    dt=parse_iso(r['publish_at'])
    r['overdue_now']=bool(dt and dt.astimezone(datetime.timezone.utc) <= now)
status_counts={}
for r in rows:
    k=str(r['runtime_status'] or 'missing')
    status_counts[k]=status_counts.get(k,0)+1
p={
    'task':'probe_wave1_remaining_schedule_v1','status':'PASS','read_only':True,
    'observed_at_utc':now.isoformat(),
    'runtime_file_count':len(rows),'state_article_count':len(articles_state),
    'status_counts':status_counts,
    'remaining_count':len(remaining),'overdue_remaining_count':sum(1 for r in remaining if r['overdue_now']),
    'remaining':remaining,
    'cms_write_attempted':False,'runtime_mutated':False,'cron_mutated':False,'queue_consumed':False,
    'publication_policy_mutated':False,'wave1_resumed':False
}
out.write_text(json.dumps(p,ensure_ascii=False,indent=2,sort_keys=True)+'\n',encoding='utf-8')
PY

echo WAVE1_REMAINING_SCHEDULE_PROBE=PASS
