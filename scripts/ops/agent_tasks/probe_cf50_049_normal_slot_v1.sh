#!/bin/bash
# Read-only verification that recurring Publisher released CF50-049 at its normal slot and completed the first 12 CF50 seeds.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
BASE="/var/lib/xyptdq-publisher/CF50-20260813-wave1"
STATE="$BASE/state.json"
RECEIPTS="$BASE/receipts"
VERIFY="$REPO/scripts/seo/verify_publication_seo.php"
KEY="lcm-creator-cf50-20260813-049"
[ -n "$RESULT_FILE" ] || exit 2

fail() {
  local phase="$1" detail="$2"
  python3 - "$RESULT_FILE" "$phase" "$detail" <<'PY'
import json,sys
out,phase,detail=sys.argv[1:]
p={'task':'probe_cf50_049_normal_slot_v1','status':'FAIL','phase':phase,'detail':detail,'read_only':True,'article_id':'LCM-CREATOR-cf50-20260813-049','cms_write_attempted':False,'runtime_mutated':False,'cron_mutated':False,'queue_consumed':False,'publication_attempted':False}
with open(out,'w',encoding='utf-8') as f: json.dump(p,f,ensure_ascii=False,indent=2,sort_keys=True); f.write('\n')
PY
  exit 20
}

[ -d "$REPO/.git" ] || fail preflight "canonical website repo missing"
[ -s "$STATE" ] || fail preflight "Publisher state missing"
[ -s "$VERIFY" ] || fail preflight "authoritative live SEO verifier missing"

python3 - "$STATE" "$KEY" "$RESULT_FILE" "$RECEIPTS" "$VERIFY" <<'PY'
import json,subprocess,sys,pathlib
state_path,key,out,receipts,verify=sys.argv[1:]
state=json.load(open(state_path,encoding='utf-8')); articles=state.get('articles') or {}
entry=articles.get(key) or {}
if entry.get('status')!='published': raise SystemExit('049 is not published in Publisher state')
cms=int(entry.get('cms_id') or 0)
if cms<=0: raise SystemExit('049 cms_id invalid')
counts={}
for e in articles.values():
    s=str((e or {}).get('status') or 'missing'); counts[s]=counts.get(s,0)+1
if len(articles)!=11:
    raise SystemExit(f'unexpected Wave1 article count: {len(articles)}')
if counts.get('published')!=11 or counts.get('scheduled',0)!=0 or counts.get('failed',0)!=0:
    raise SystemExit('unexpected Wave1 state counts after 049')
receipt=pathlib.Path(receipts)/f'{key}.{cms}.json'
if not receipt.is_file(): raise SystemExit('049 publication receipt missing')
proc=subprocess.run(['php',verify,f'--receipt={receipt}'],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
if proc.returncode!=0:
    detail=(proc.stderr or proc.stdout or 'no verifier output').strip()[-1000:]
    raise SystemExit('049 authoritative live SEO verification failed: '+detail)
url=f'https://www.laocaimi.org/index.php?c=show&id={cms}'
p={
 'task':'probe_cf50_049_normal_slot_v1','status':'PASS','phase':'complete','read_only':True,
 'article_id':'LCM-CREATOR-cf50-20260813-049','article_key':key,'cms_id':cms,'published_url':url,
 'publisher_state_status':'published','published_at':entry.get('published_at'),
 'wave1_state_article_count':len(articles),'wave1_published_count':counts.get('published',0),
 'wave1_scheduled_count':counts.get('scheduled',0),'wave1_failed_count':counts.get('failed',0),
 'publication_receipt':str(receipt),'authoritative_live_seo_verify':'PASS',
 'overall_first12_seed_progress':'12/12',
 'search_discovery_checkpoint_required':True,
 'wave_b_must_remain_blocked_until_gate_conclusion':True,
 'cms_write_attempted':False,'runtime_mutated':False,'cron_mutated':False,'queue_consumed':False,'publication_attempted':False
}
with open(out,'w',encoding='utf-8') as f: json.dump(p,f,ensure_ascii=False,indent=2,sort_keys=True); f.write('\n')
PY

echo CF50_049_NORMAL_SLOT_PROBE=PASS
