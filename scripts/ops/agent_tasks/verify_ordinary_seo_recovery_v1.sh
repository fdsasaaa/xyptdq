#!/bin/bash
# Read-only closeout: observe natural :05 promotion and :07 Publisher polls.
set -euo pipefail
umask 077
: "${XYPTDQ_AGENT_RESULT_FILE:?result file required}"
python3 - "$XYPTDQ_AGENT_RESULT_FILE" <<'PY'
import datetime as dt, json, pathlib, re, sys, time
out=pathlib.Path(sys.argv[1]); root=pathlib.Path('/var/lib/xyptdq-content'); pub=pathlib.Path('/var/lib/xyptdq-publisher')
threshold=dt.datetime(2026,10,31,1,5,tzinfo=dt.timezone.utc)
publisher_threshold=threshold+dt.timedelta(minutes=2)
deadline=time.monotonic()+300
def load(p):return json.loads(p.read_text())
result={'task':'verify_ordinary_seo_recovery_v1','status':'BLOCKED','read_only':True,'cms_write':False,'cron_write':False,'publisher_invoked':False}
while True:
    try:
        promotion=load(root/'ordinary-seo/promotion-last-run.json')
        observed=dt.datetime.fromisoformat(promotion['observed_at'])
        assert observed>=threshold and observed.minute==5 and promotion['status']=='PASS'
        assert promotion['added_this_run']==0 and promotion['active_future_scheduled']==1
        paths=sorted(pathlib.Path('/var/log/xyptdq-publisher').glob('run_*.log'))
        assert paths
        log=paths[-1]; started=dt.datetime.strptime(log.stem[4:],'%Y%m%dT%H%M%SZ').replace(tzinfo=dt.timezone.utc)
        assert started>=publisher_threshold
        lines=log.read_text().splitlines()
        assert 'result=PASS' in lines and 'seo_verification=PASS' in lines
        counts=next(s for s in lines if s.startswith('[filequeue] source='))
        assert re.search(r'\bsource=2 due=0\b',counts)
        reconciliation=[json.loads(s) for s in lines if s.startswith('{') and '"changed_count"' in s]
        assert reconciliation and reconciliation[-1]['status']=='PASS' and reconciliation[-1]['changed_count']==0
        ledger=load(root/'intake/state.json'); state=load(pub/'ordinary-seo/state.json')
        canary=ledger['records']['LCM-ANGLE-0b6f9c192c45dc31:public-r1']
        target=ledger['records']['LCM-ANGLE-11c1d01b80765af0:public-r1']
        assert canary['lifecycle_state']=='published' and canary['cms_id']==104
        assert target['lifecycle_state']=='scheduled' and target['cms_id'] is None
        assert len(state['articles'])==1 and state['articles']['lcm-angle-0b6f9c192c45dc31']['status']=='published'
        result.update({'status':'PASS','observed_at':dt.datetime.now(dt.timezone.utc).isoformat(),
                       'natural_promotion':promotion,'natural_publisher_log':log.name,
                       'natural_publisher_git_sha':next(s.split('=',1)[1] for s in lines if s.startswith('git_sha=')),
                       'natural_publisher_counts':counts,'natural_publisher_result':'PASS',
                       'natural_ledger_reconciliation':reconciliation[-1],
                       'ledger_count':len(ledger['records']),
                       'ledger_lifecycle_counts':{k:sum(r.get('lifecycle_state')==k for r in ledger['records'].values()) for k in ('draft','scheduled','published')},
                       'canary_104_published':True,'new_target_still_scheduled':True,
                       'new_target_publish_at':'2026-10-31T10:00:00+08:00','new_publication_observed':False})
        break
    except (AssertionError,KeyError,ValueError,StopIteration,FileNotFoundError):
        if time.monotonic()>=deadline:
            result['blocking_item']='natural_promotion_or_publisher_proof_not_observed_before_deadline'
            break
        time.sleep(5)
out.write_text(json.dumps(result,ensure_ascii=False,indent=2,sort_keys=True)+'\n')
print('ORDINARY_SEO_NATURAL_POLLS='+result['status'])
raise SystemExit(0 if result['status']=='PASS' else 1)
PY
