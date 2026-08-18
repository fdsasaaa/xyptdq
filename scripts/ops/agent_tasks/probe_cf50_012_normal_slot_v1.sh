#!/bin/bash
# Read-only verification that recurring Publisher released CF50-012 at its normal slot.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
BASE="/var/lib/xyptdq-publisher/CF50-20260813-wave1"
STATE="$BASE/state.json"
RECEIPTS="$BASE/receipts"
VERIFY="$REPO/scripts/seo/verify_publication_seo.php"
KEY="lcm-creator-cf50-20260813-012"
ARTICLE_ID="LCM-CREATOR-cf50-20260813-012"
NEXT_KEY="lcm-creator-cf50-20260813-022"
[ -n "$RESULT_FILE" ] || exit 2

fail() {
  local phase="$1" detail="$2"
  python3 - "$RESULT_FILE" "$phase" "$detail" <<'PY'
import json,sys
out,phase,detail=sys.argv[1:]
p={'task':'probe_cf50_012_normal_slot_v1','status':'FAIL','phase':phase,'detail':detail,'read_only':True,'article_id':'LCM-CREATOR-cf50-20260813-012','cms_write_attempted':False,'runtime_mutated':False,'cron_mutated':False,'queue_consumed':False,'publication_attempted':False}
with open(out,'w',encoding='utf-8') as f: json.dump(p,f,ensure_ascii=False,indent=2,sort_keys=True); f.write('\n')
PY
  exit 20
}

[ -d "$REPO/.git" ] || fail preflight "canonical website repo missing"
[ -s "$STATE" ] || fail preflight "Publisher state missing"
[ -s "$VERIFY" ] || fail preflight "authoritative live SEO verifier missing"

python3 - "$STATE" "$KEY" "$NEXT_KEY" "$RESULT_FILE" "$RECEIPTS" "$VERIFY" <<'PY'
import json,subprocess,sys,pathlib
state_path,key,next_key,out,receipts,verify=sys.argv[1:]
state=json.load(open(state_path,encoding='utf-8')); articles=state.get('articles') or {}
entry=articles.get(key) or {}; nxt=articles.get(next_key) or {}
if entry.get('status')!='published': raise SystemExit('012 is not published in Publisher state')
cms=int(entry.get('cms_id') or 0)
if cms<=0: raise SystemExit('012 cms_id invalid')
if nxt.get('status')!='scheduled': raise SystemExit('022 is not still scheduled')
if int(nxt.get('cms_id') or 0)!=0: raise SystemExit('022 already has cms_id; possible premature consumption')
counts={}
for e in articles.values():
    s=str((e or {}).get('status') or 'missing'); counts[s]=counts.get(s,0)+1
if counts.get('published')!=7 or counts.get('scheduled')!=4 or counts.get('failed',0)!=0:
    raise SystemExit('unexpected Wave1 state counts after 012')
receipt=pathlib.Path(receipts)/f'{key}.{cms}.json'
if not receipt.is_file(): raise SystemExit('012 publication receipt missing')
proc=subprocess.run(['php',verify,f'--receipt={receipt}'],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
if proc.returncode!=0:
    detail=(proc.stderr or proc.stdout or 'no verifier output').strip()[-1000:]
    raise SystemExit('012 authoritative live SEO verification failed: '+detail)
url=f'https://www.laocaimi.org/index.php?c=show&id={cms}'
p={
 'task':'probe_cf50_012_normal_slot_v1','status':'PASS','phase':'complete','read_only':True,
 'article_id':'LCM-CREATOR-cf50-20260813-012','article_key':key,'cms_id':cms,'published_url':url,
 'publisher_state_status':'published','published_at':entry.get('published_at'),
 'wave1_state_article_count':len(articles),'wave1_published_count':counts.get('published',0),
 'wave1_scheduled_count':counts.get('scheduled',0),'wave1_failed_count':counts.get('failed',0),
 'publication_receipt':str(receipt),'authoritative_live_seo_verify':'PASS',
 'next_article_id':'LCM-CREATOR-cf50-20260813-022','next_runtime_status':nxt.get('status'),
 'next_cms_id':nxt.get('cms_id'),'expected_next_publish_at':'2026-08-18T19:00:00+08:00',
 'overall_first12_seed_progress':'8/12',
 'cms_write_attempted':False,'runtime_mutated':False,'cron_mutated':False,'queue_consumed':False,'publication_attempted':False
}
with open(out,'w',encoding='utf-8') as f: json.dump(p,f,ensure_ascii=False,indent=2,sort_keys=True); f.write('\n')
PY

echo CF50_012_NORMAL_SLOT_PROBE=PASS
