#!/bin/bash
# Read-only diagnostic verification for CF50-049 final first-wave Seed.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
BASE="/var/lib/xyptdq-publisher/CF50-20260813-wave1"
STATE="$BASE/state.json"
RECEIPTS="$BASE/receipts"
VERIFY="$REPO/scripts/seo/verify_publication_seo.php"
KEY="lcm-creator-cf50-20260813-049"
EXPECTED_PUBLISH_AT="2026-08-20T10:00:00+08:00"
VERIFY_GRACE_MINUTES="20"
[ -n "$RESULT_FILE" ] || exit 2

fail() {
  local phase="$1" detail="$2"
  python3 - "$RESULT_FILE" "$phase" "$detail" <<'PY'
import json,sys
out,phase,detail=sys.argv[1:]
p={
  'task':'probe_cf50_049_normal_slot_v2','status':'FAIL','phase':phase,'detail':detail,
  'read_only':True,'article_id':'LCM-CREATOR-cf50-20260813-049',
  'cms_write_attempted':False,'runtime_mutated':False,'cron_mutated':False,
  'queue_consumed':False,'publication_attempted':False
}
with open(out,'w',encoding='utf-8') as f:
    json.dump(p,f,ensure_ascii=False,indent=2,sort_keys=True); f.write('\n')
PY
  exit 20
}

[ -d "$REPO/.git" ] || fail preflight "canonical website repo missing"
[ -s "$STATE" ] || fail preflight "Publisher state missing"
[ -s "$VERIFY" ] || fail preflight "authoritative live SEO verifier missing"

set +e
python3 - "$STATE" "$KEY" "$RESULT_FILE" "$RECEIPTS" "$VERIFY" "$EXPECTED_PUBLISH_AT" "$VERIFY_GRACE_MINUTES" <<'PY'
import datetime,json,subprocess,sys,pathlib,traceback
state_path,key,out,receipts,verify,expected_publish_at,grace_minutes=sys.argv[1:]
base={
 'task':'probe_cf50_049_normal_slot_v2','read_only':True,
 'article_id':'LCM-CREATOR-cf50-20260813-049','article_key':key,
 'cms_write_attempted':False,'runtime_mutated':False,'cron_mutated':False,
 'queue_consumed':False,'publication_attempted':False,
 'search_discovery_checkpoint_required':True,
 'wave_b_must_remain_blocked_until_gate_conclusion':True,
 'expected_publish_at':expected_publish_at,
}
try:
    expected=datetime.datetime.fromisoformat(expected_publish_at)
    grace=datetime.timedelta(minutes=int(grace_minutes))
    verify_after=expected+grace
    now=datetime.datetime.now(datetime.timezone.utc)
    state=json.load(open(state_path,encoding='utf-8'))
    articles=state.get('articles') or {}
    entry=articles.get(key) or {}
    counts={}
    for e in articles.values():
        s=str((e or {}).get('status') or 'missing')
        counts[s]=counts.get(s,0)+1
    cms=int(entry.get('cms_id') or 0)
    receipt=pathlib.Path(receipts)/f'{key}.{cms}.json' if cms>0 else pathlib.Path(receipts)/'__invalid_cms__.json'
    p=dict(base)
    p.update({
      'phase':'inspect',
      'observed_at':now.isoformat(),
      'verification_due_after':verify_after.isoformat(),
      'publisher_state_article_count':len(articles),
      'publisher_state_counts':counts,
      'article_state_status':entry.get('status'),
      'cms_id':cms,
      'published_at':entry.get('published_at'),
      'receipt_path':str(receipt),
      'receipt_exists':receipt.is_file(),
    })

    # The 021 pause/rebase shifted 049 from 2026-08-19 19:00 to 2026-08-20 10:00 +08:00.
    # Before the rebased slot plus a short cron/verification grace window, scheduled is healthy.
    if now < verify_after.astimezone(datetime.timezone.utc):
        problems=[]
        if len(articles)!=11: problems.append(f'unexpected Wave1 article count: {len(articles)}')
        if counts.get('published')!=10 or counts.get('scheduled',0)!=1 or counts.get('failed',0)!=0:
            problems.append('unexpected Wave1 state counts before rebased 049 slot')
        if entry.get('status')!='scheduled':
            problems.append('049 should remain scheduled before rebased final slot')
        if cms!=0:
            problems.append('049 has cms_id before rebased final slot')
        if problems:
            p.update({'status':'FAIL','phase':'pre_slot_verification','problems':problems})
            rc=20
        else:
            p.update({
              'status':'PASS','phase':'not_due',
              'detail':'049 is correctly waiting for the rebased final Seed slot',
              'overall_first12_seed_progress':'11/12_waiting_final_slot',
              'authoritative_live_seo_verify':'NOT_DUE'
            })
            rc=0
    else:
        problems=[]
        if entry.get('status')!='published': problems.append('049 is not published in Publisher state after rebased slot')
        if cms<=0: problems.append('049 cms_id invalid after rebased slot')
        if len(articles)!=11: problems.append(f'unexpected Wave1 article count: {len(articles)}')
        if counts.get('published')!=11 or counts.get('scheduled',0)!=0 or counts.get('failed',0)!=0:
            problems.append('unexpected Wave1 state counts after rebased 049 slot')
        if cms>0 and not receipt.is_file(): problems.append('049 publication receipt missing')
        verifier_rc=None; verifier_detail=''
        if cms>0 and receipt.is_file():
            proc=subprocess.run(['php',verify,f'--receipt={receipt}'],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
            verifier_rc=proc.returncode
            verifier_detail=(proc.stderr or proc.stdout or '').strip()[-2000:]
            if verifier_rc!=0: problems.append('049 authoritative live SEO verification failed')
        p['verifier_exit_code']=verifier_rc
        p['verifier_detail']=verifier_detail
        if problems:
            p['status']='FAIL'; p['phase']='verification'; p['problems']=problems
            rc=20
        else:
            p.update({
              'status':'PASS','phase':'complete',
              'published_url':f'https://www.laocaimi.org/index.php?c=show&id={cms}',
              'publication_receipt':str(receipt),
              'authoritative_live_seo_verify':'PASS',
              'overall_first12_seed_progress':'12/12'
            })
            rc=0
except Exception as e:
    p=dict(base)
    p.update({'status':'FAIL','phase':'exception','detail':str(e),'traceback':traceback.format_exc()[-2000:]})
    rc=20
with open(out,'w',encoding='utf-8') as f:
    json.dump(p,f,ensure_ascii=False,indent=2,sort_keys=True); f.write('\n')
raise SystemExit(rc)
PY
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
  exit "$rc"
fi

echo CF50_049_NORMAL_SLOT_PROBE_V2=PASS
