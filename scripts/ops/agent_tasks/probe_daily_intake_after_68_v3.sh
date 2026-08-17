#!/bin/bash
set -euo pipefail
R="${XYPTDQ_AGENT_RESULT_FILE:-}"
I="${XYPTDQ_INTAKE_ROOT:-/var/lib/xyptdq-content/intake}"
L="${XYPTDQ_INTAKE_LOG_DIR:-/var/log/xyptdq-intake}"
C="${XYPTDQ_INTAKE_CRON_FILE:-/etc/cron.d/xyptdq-intake}"
[ -n "$R" ] || exit 2
python3 - "$R" "$I" "$L" "$C" <<'PY'
import json,sys,pathlib,re,traceback
out=pathlib.Path(sys.argv[1]); root=pathlib.Path(sys.argv[2]); logs=pathlib.Path(sys.argv[3]); cron=pathlib.Path(sys.argv[4])
base={'task':'probe_daily_intake_after_68_v3','read_only':True,'runtime_mutation_attempted':False,'cms_write_attempted':False,'scheduled_queue_mutated':False,'publisher_invoked':False,'publisher_cron_mutated':False,'intake_cron_mutated':False,'publication_queue_consumed':False}
try:
 s=root/'source/caipiaowenzhang'; lp=root/'state.json'; dd=root/'drafts'
 m1=s/'articles/public_release/manifests/CF50-20260813.json'; m2=s/'articles/public_release/manifests/DAILY-20260817.json'
 assert lp.is_file() and dd.is_dir() and m1.is_file() and m2.is_file() and logs.is_dir() and cron.is_file()
 a=json.loads(m1.read_text(encoding='utf-8')); b=json.loads(m2.read_text(encoding='utf-8'))
 assert a.get('approved_public_release_count')==45 and b.get('approved_public_release_count')==23
 revs=[x.get('revision_id') for x in b.get('articles') or []]; assert len(revs)==23 and len(set(revs))==23 and all(revs)
 led=json.loads(lp.read_text(encoding='utf-8')); rec=led.get('records') or {}; assert isinstance(rec,dict) and len(rec)==56
 assert all(r in rec for r in revs)
 frozen={'LCM-CREATOR-cf50-20260813-020','LCM-CREATOR-cf50-20260813-029','LCM-CREATOR-cf50-20260813-038','LCM-CREATOR-cf50-20260813-039','LCM-CREATOR-cf50-20260813-040'}
 for rev,x in rec.items():
  assert x.get('lifecycle_state')=='draft' and x.get('cms_id') is None and x.get('scheduled_at') is None and x.get('published_at') is None
  aid=str(x.get('article_id') or ''); assert aid not in frozen
  p=pathlib.Path(str(x.get('draft_path') or '')); assert p.is_file(); d=json.loads(p.read_text(encoding='utf-8'))
  assert d.get('publication_state')=='draft' and 'publish_at' not in d and str(d.get('source_article_id') or '')==aid
 fs=list(dd.glob('*.json')); assert len(fs)==56
 for p in fs:
  d=json.loads(p.read_text(encoding='utf-8')); assert d.get('publication_state')=='draft' and 'publish_at' not in d and str(d.get('source_article_id') or '') not in frozen
 hit=None; obs=[]
 for p in sorted(logs.glob('run_*.log')):
  m=re.match(r'^run_(\d{8}T\d{6}Z)\.log$',p.name)
  if not m or m.group(1)<'20260817T012300Z': continue
  try: x=json.loads(p.read_text(encoding='utf-8'))
  except Exception: continue
  row=(p.name,x.get('status'),x.get('source_commit'),x.get('candidate_count_before'),x.get('ledger_known_before'),len(x.get('selected_revision_ids') or [])); obs.append(row)
  if row[1:] == ('PASS','93fd1f9d021ce191780a66f501ed2634db141640',23,33,23): hit=(p,x)
 assert hit is not None, obs
 active=[]
 for q in list(pathlib.Path('/etc/cron.d').glob('*'))+[pathlib.Path('/etc/crontab')]:
  if q.is_file(): active += [z.strip() for z in q.read_text(encoding='utf-8',errors='ignore').splitlines() if z.strip() and not z.lstrip().startswith('#') and 'run_incremental_inventory_intake.sh' in z]
 assert len(active)==1 and '23 * * * * root XYPTDQ_INTAKE_MODE=auto XYPTDQ_INTAKE_LIMIT=25 /bin/bash' in active[0]
 p,x=hit; z=dict(base); z.update({'status':'PASS','phase':'complete','detail':'09:23 natural intake consumed all 23 DAILY-20260817 public-r1 revisions into Draft-only state','upstream_formal_public_r1_total':68,'previous_formal_public_r1':45,'daily_20260817_public_r1':23,'ledger_records_current':56,'runtime_draft_files_current':56,'daily_20260817_revisions_in_ledger':23,'new_draft_candidates_current':0,'natural_intake_log':p.name,'natural_intake_source_commit':x.get('source_commit'),'natural_intake_candidate_count_before':23,'natural_intake_ledger_known_before':33,'natural_intake_selected_count':23,'intake_cron_count':1,'intake_cron_schedule':'23 * * * *','cf50_final5_release_authorized':False,'cf50_frozen_final5_count':5}); out.write_text(json.dumps(z,ensure_ascii=False,indent=2,sort_keys=True)+'\n',encoding='utf-8'); print('PASS')
except Exception as e:
 z=dict(base); z.update({'status':'FAIL','phase':'audit','detail':str(e)}); out.write_text(json.dumps(z,ensure_ascii=False,indent=2,sort_keys=True)+'\n',encoding='utf-8'); traceback.print_exc(); raise SystemExit(20)
PY
