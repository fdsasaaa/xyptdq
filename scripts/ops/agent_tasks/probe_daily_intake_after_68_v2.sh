#!/bin/bash
set -euo pipefail
umask 077
RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
INTAKE_ROOT="${XYPTDQ_INTAKE_ROOT:-/var/lib/xyptdq-content/intake}"
LOG_DIR="${XYPTDQ_INTAKE_LOG_DIR:-/var/log/xyptdq-intake}"
CRON_FILE="${XYPTDQ_INTAKE_CRON_FILE:-/etc/cron.d/xyptdq-intake}"
[ -n "$RESULT_FILE" ] || exit 2
python3 - "$RESULT_FILE" "$INTAKE_ROOT" "$LOG_DIR" "$CRON_FILE" <<'PY'
import json,sys,pathlib,re,traceback
out=pathlib.Path(sys.argv[1]); root=pathlib.Path(sys.argv[2]); log_dir=pathlib.Path(sys.argv[3]); cron_file=pathlib.Path(sys.argv[4])
base={
  'task':'probe_daily_intake_after_68_v2','read_only':True,
  'runtime_mutation_attempted':False,'cms_write_attempted':False,'scheduled_queue_mutated':False,
  'publisher_invoked':False,'publisher_cron_mutated':False,'intake_cron_mutated':False,
  'publication_queue_consumed':False
}
try:
    source=root/'source'/'caipiaowenzhang'
    ledger_p=root/'state.json'; drafts=root/'drafts'
    cf50_p=source/'articles/public_release/manifests/CF50-20260813.json'
    daily_p=source/'articles/public_release/manifests/DAILY-20260817.json'
    assert ledger_p.is_file(), 'ledger missing'
    assert drafts.is_dir(), 'Draft dir missing'
    assert cf50_p.is_file(), 'CF50 manifest missing in synced source cache'
    assert daily_p.is_file(), 'DAILY-20260817 manifest missing in synced source cache'
    assert log_dir.is_dir(), 'intake log dir missing'
    assert cron_file.is_file(), 'intake cron missing'

    cf50=json.loads(cf50_p.read_text(encoding='utf-8'))
    daily=json.loads(daily_p.read_text(encoding='utf-8'))
    assert cf50.get('approved_public_release_count')==45, cf50.get('approved_public_release_count')
    assert daily.get('approved_public_release_count')==23, daily.get('approved_public_release_count')
    daily_articles=daily.get('articles') or []
    daily_revs=[a.get('revision_id') for a in daily_articles]
    assert len(daily_revs)==23 and len(set(daily_revs))==23 and all(daily_revs), 'daily manifest revision IDs invalid'

    ledger=json.loads(ledger_p.read_text(encoding='utf-8'))
    rec=ledger.get('records') or {}
    assert isinstance(rec,dict) and len(rec)==56, f'ledger records={len(rec)}'
    missing=[r for r in daily_revs if r not in rec]
    assert not missing, f'daily revisions missing from ledger: {missing}'

    frozen={'LCM-CREATOR-cf50-20260813-020','LCM-CREATOR-cf50-20260813-029','LCM-CREATOR-cf50-20260813-038','LCM-CREATOR-cf50-20260813-039','LCM-CREATOR-cf50-20260813-040'}
    for rev,r in rec.items():
        assert r.get('lifecycle_state')=='draft', f'{rev}: lifecycle={r.get("lifecycle_state")}'
        assert r.get('cms_id') is None, f'{rev}: cms_id present'
        assert r.get('scheduled_at') is None, f'{rev}: scheduled_at present'
        assert r.get('published_at') is None, f'{rev}: published_at present'
        aid=str(r.get('article_id') or '')
        assert aid not in frozen, f'frozen final5 entered ledger: {aid}'
        dp=pathlib.Path(str(r.get('draft_path') or ''))
        assert dp.is_file(), f'{rev}: draft missing'
        d=json.loads(dp.read_text(encoding='utf-8'))
        assert d.get('publication_state')=='draft', f'{rev}: publication_state={d.get("publication_state")}'
        assert 'publish_at' not in d, f'{rev}: publish_at present'
        assert str(d.get('source_article_id') or '')==aid, f'{rev}: source article mismatch'

    draft_files=list(drafts.glob('*.json'))
    assert len(draft_files)==56, f'draft files={len(draft_files)}'
    for p in draft_files:
        d=json.loads(p.read_text(encoding='utf-8'))
        assert d.get('publication_state')=='draft', f'{p.name}: not draft'
        assert 'publish_at' not in d, f'{p.name}: publish_at present'
        assert str(d.get('source_article_id') or '') not in frozen, f'{p.name}: frozen final5 present'

    rx=re.compile(r'^run_(\d{8}T\d{6}Z)\.log$')
    matched=[]; observed=[]
    for p in sorted(log_dir.glob('run_*.log')):
        m=rx.match(p.name)
        if not m or m.group(1) < '20260817T012300Z':
            continue
        try: x=json.loads(p.read_text(encoding='utf-8'))
        except Exception: continue
        row={'file':p.name,'status':x.get('status'),'source_commit':x.get('source_commit'),'candidate_count_before':x.get('candidate_count_before'),'ledger_known_before':x.get('ledger_known_before'),'selected_count':len(x.get('selected_revision_ids') or [])}
        observed.append(row)
        if x.get('status')=='PASS' and x.get('source_commit')=='93fd1f9d021ce191780a66f501ed2634db141640' and x.get('candidate_count_before')==23 and x.get('ledger_known_before')==33 and len(x.get('selected_revision_ids') or [])==23:
            matched.append((p,x))
    assert matched, f'no matching 09:23 intake transition; observed={observed}'
    p,x=matched[-1]

    active=[]
    for path in list(pathlib.Path('/etc/cron.d').glob('*'))+[pathlib.Path('/etc/crontab')]:
        if not path.is_file(): continue
        for line in path.read_text(encoding='utf-8',errors='ignore').splitlines():
            s=line.strip()
            if s and not s.startswith('#') and 'run_incremental_inventory_intake.sh' in s:
                active.append(s)
    assert len(active)==1, f'active intake cron count={len(active)}'
    assert '23 * * * * root XYPTDQ_INTAKE_MODE=auto XYPTDQ_INTAKE_LIMIT=25 /bin/bash' in active[0], active[0]

    payload=dict(base)
    payload.update({
      'status':'PASS','phase':'complete',
      'detail':'09:23 natural intake consumed all 23 newly formal DAILY-20260817 public-r1 revisions into Draft-only runtime state',
      'upstream_formal_public_r1_total':68,'previous_formal_public_r1':45,'daily_20260817_public_r1':23,
      'ledger_records_current':56,'runtime_draft_files_current':56,'daily_20260817_revisions_in_ledger':23,
      'new_draft_candidates_current':0,
      'natural_intake_log':p.name,'natural_intake_source_commit':x.get('source_commit'),
      'natural_intake_candidate_count_before':x.get('candidate_count_before'),'natural_intake_ledger_known_before':x.get('ledger_known_before'),
      'natural_intake_selected_count':len(x.get('selected_revision_ids') or []),
      'intake_cron_count':1,'intake_cron_schedule':'23 * * * *',
      'cf50_final5_release_authorized':False,'cf50_frozen_final5_count':5
    })
    out.write_text(json.dumps(payload,ensure_ascii=False,indent=2,sort_keys=True)+'\n',encoding='utf-8')
    print('DAILY_INTAKE_AFTER_68_PROBE_V2=PASS')
except Exception as e:
    payload=dict(base)
    payload.update({'status':'FAIL','phase':'audit','detail':str(e)})
    out.write_text(json.dumps(payload,ensure_ascii=False,indent=2,sort_keys=True)+'\n',encoding='utf-8')
    traceback.print_exc()
    raise SystemExit(20)
PY
