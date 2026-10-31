#!/bin/bash
# Fresh, read-only runtime evidence; never publishes, schedules or edits cron/CMS.
set -euo pipefail
umask 077
: "${XYPTDQ_AGENT_RESULT_FILE:?result file required}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
TMP=$(mktemp -d /tmp/xyptdq-runtime-audit.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
XYPTDQ_WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}" php /dev/stdin "$REPO" > "$TMP/pages.json" <<'PHP'
<?php
require $argv[1].'/scripts/content/cms_publish_native_adapter.php';
$c=xyptdq_native_load_db_config(); $pdo=xyptdq_native_open_pdo($c);
$prefix=xyptdq_native_identifier((string)($c['DBPrefix']??'dr_'),'prefix');
$out=['pages'=>[], 'comparison'=>[]]; $rows=[];
foreach ([105,106] as $id) {
    $item=['id'=>$id]; $parts=[];
    foreach (['1_news','1_news_data_0'] as $suffix) {
        $table=$prefix.$suffix;
        if (!xyptdq_native_table_exists($pdo,(string)$c['database'],$table)) {continue;}
        $q=$pdo->prepare('SELECT * FROM `'.$table.'` WHERE id=?'); $q->execute([$id]); $row=$q->fetch();
        if (!$row) {continue;}
        if ($suffix==='1_news') {
            foreach (['title','catid','status','url','description'] as $k) {$item[$k]=$row[$k]??null;}
        }
        foreach (['id','uid','author','hits','inputtime','updatetime','displayorder'] as $k) {unset($row[$k]);}
        ksort($row); $parts[$suffix]=$row;
        $item[$suffix.'_sha256']=hash('sha256',json_encode($row,JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES));
        $item[$suffix.'_fields']=array_keys($row);
    }
    $rows[$id]=$parts; $out['pages'][]=$item;
}
foreach (array_unique(array_merge(array_keys($rows[105]??[]),array_keys($rows[106]??[]))) as $suffix) {
    $a=$rows[105][$suffix]??[]; $b=$rows[106][$suffix]??[]; $diff=[];
    foreach (array_unique(array_merge(array_keys($a),array_keys($b))) as $k) {if (($a[$k]??null)!==($b[$k]??null)) {$diff[]=$k;}}
    $out['comparison'][$suffix]=['identical'=>$a===$b,'different_fields'=>$diff];
}
echo json_encode($out,JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
PHP
python3 - "$XYPTDQ_AGENT_RESULT_FILE" "$TMP/pages.json" "$REPO" <<'PY'
import collections, datetime, hashlib, json, pathlib, subprocess, sys
out, pages, repo = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3])
def load(p):
    return json.loads(p.read_text()) if p.is_file() else None
def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest() if p.is_file() else None
root=pathlib.Path('/var/lib/xyptdq-content'); pub=pathlib.Path('/var/lib/xyptdq-publisher')
state=load(pub/'ordinary-seo/state.json') or {}; ledger=load(root/'intake/state.json') or {}
queued=[]
for p in sorted((root/'ordinary-seo/scheduled').glob('*.json')):
    q=load(p); e=state.get('articles',{}).get(q.get('article_key'),{})
    rec=ledger.get('records',{}).get(q.get('source_revision_id'),{})
    item={k:q.get(k) for k in ('article_key','source_article_id','source_revision_id','source_batch_id','publish_at')}
    item.update({'publisher_status':e.get('status'),'cms_id':e.get('cms_id'),'ledger_lifecycle':rec.get('lifecycle_state'),'ledger_cms_id':rec.get('cms_id')})
    queued.append(item)
cron={}
for name in ('publisher','promotion','intake'):
    p=pathlib.Path('/etc/cron.d/xyptdq-'+name)
    lines=[s for s in p.read_text().splitlines() if s.strip() and not s.lstrip().startswith('#')] if p.is_file() else []
    # Only explicitly allowlisted settings and schedule prefixes leave the server.
    cron[name]={'exists':p.is_file(),'sha256':sha(p),'schedules':[' '.join(s.split()[:5]) for s in lines if len(s.split())>=7], 'result_path_present':any('XYPTDQ_AGENT_RESULT_FILE=' in s for s in lines),'timezone_setting':next((s for s in lines if s.startswith('CRON_TZ=')),None)}
drafts=[]
for p in (root/'intake/drafts').glob('*.draft.json'):
    q=load(p); drafts.append(q.get('source_batch_id','unknown'))
payload={'task':'audit_ordinary_seo_runtime_v1','status':'PASS','read_only':True,'cms_write':False,'cron_write':False,'publisher_invoked':False,'observed_at':datetime.datetime.now(datetime.timezone.utc).isoformat(), 'repo_head':subprocess.check_output(['git','-C',str(repo),'rev-parse','HEAD'],text=True).strip(),'cron':cron,'ordinary_queue':queued,'ordinary_publisher_counts':dict(collections.Counter(v.get('status','unknown') for v in state.get('articles',{}).values())),'ledger_count':len(ledger.get('records',{})),'ledger_lifecycle_counts':dict(collections.Counter(v.get('lifecycle_state','unknown') for v in ledger.get('records',{}).values())),'draft_batches':dict(collections.Counter(drafts)), 'duplicate_page_evidence':load(pages),'baseline_hashes':{'legacy_state':sha(pub/'state.json'),'cf50_state':sha(pub/'CF50-20260813-wave1/state.json')}}
out.write_text(json.dumps(payload,ensure_ascii=False,indent=2,sort_keys=True)+'\n')
print('ORDINARY_SEO_RUNTIME_AUDIT=PASS')
PY
