#!/bin/bash
# Read-only production diagnostic for CF50-021 Sitemap/canonical mismatch.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
DB_CONFIG="${XYPTDQ_DB_CONFIG:-$WEBROOT/config/database.php}"
LOCAL_SITEMAP="${XYPTDQ_SITEMAP:-$WEBROOT/sitemap.xml}"
LIVE_SITEMAP="https://www.laocaimi.org/sitemap.xml"
BASE="/var/lib/xyptdq-publisher/CF50-20260813-wave1"
CMS_ID=94
EXPECTED="https://www.laocaimi.org/index.php?c=show&id=94"
SLUG="ffc-five-direct-distinct4"

[ -n "$RESULT_FILE" ] || exit 2
[ -f "$DB_CONFIG" ] || exit 3

TMP=$(mktemp -d /tmp/xyptdq-021-sitemap-diagnostic.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# Read only routing-relevant CMS fields. Never print credentials.
php - "$DB_CONFIG" "$CMS_ID" "$TMP/db.json" <<'PHP'
<?php
$dbConfig=$argv[1]; $id=(int)$argv[2]; $out=$argv[3];
$db=[]; require $dbConfig;
if (!isset($db['default']) || !is_array($db['default'])) exit(10);
$c=$db['default'];
$host=(string)($c['hostname']??'127.0.0.1');
$user=(string)($c['username']??'');
$pass=(string)($c['password']??'');
$name=(string)($c['database']??'');
$prefix=(string)($c['DBPrefix']??'dr_');
$pdo=new PDO('mysql:host='.$host.';dbname='.$name.';charset=utf8mb4',$user,$pass,[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC]);
$rows=[];
foreach (['news','xm'] as $mid) {
  $table=str_replace('`','',$prefix.'1_'.$mid);
  $q=$pdo->prepare("SELECT id,url,status,updatetime FROM `{$table}` WHERE id=:id LIMIT 1");
  try {$q->execute([':id'=>$id]); $r=$q->fetch();} catch(Throwable $e) {$r=false;}
  if ($r) {$rows[]=['mid'=>$mid,'id'=>(int)$r['id'],'url'=>(string)($r['url']??''),'status'=>(int)($r['status']??0),'updatetime'=>(int)($r['updatetime']??0)];}
}
$shareTable=str_replace('`','',$prefix.'1_share_index');
$share=[];
try {
  $q=$pdo->prepare("SELECT id,mid FROM `{$shareTable}` WHERE id=:id");
  $q->execute([':id'=>$id]);
  foreach($q as $r){$share[]=['id'=>(int)$r['id'],'mid'=>(string)$r['mid']];}
} catch(Throwable $e) {}
file_put_contents($out,json_encode(['cms_rows'=>$rows,'share_index_rows'=>$share],JSON_UNESCAPED_SLASHES|JSON_UNESCAPED_UNICODE|JSON_PRETTY_PRINT));
PHP

curl -skL --max-time 25 -o "$TMP/live_sitemap.xml" "$LIVE_SITEMAP" || true
curl -skL --max-time 25 -o "$TMP/page.html" "$EXPECTED" || true

VERIFY=$(find "$BASE/seo-verification" -maxdepth 1 -type f -name "*.94.json" 2>/dev/null | head -n1 || true)
LOG=$(find /var/log/xyptdq-publisher -maxdepth 1 -type f -name 'run_*.log' 2>/dev/null | sort | tail -n1 || true)

python3 - "$RESULT_FILE" "$TMP/db.json" "$LOCAL_SITEMAP" "$TMP/live_sitemap.xml" "$TMP/page.html" "$VERIFY" "$LOG" "$EXPECTED" "$SLUG" <<'PY'
import json,sys,re,html,pathlib
(out,dbp,localp,livep,pagep,verifyp,logp,expected,slug)=sys.argv[1:]
db=json.load(open(dbp,encoding='utf-8'))
def read(p):
    try:return pathlib.Path(p).read_text(encoding='utf-8',errors='ignore')
    except Exception:return ''
def locs(xml):
    return [html.unescape(x.strip()) for x in re.findall(r'<loc>(.*?)</loc>',xml,re.I|re.S)]
def relevant(items,candidates):
    out=[]
    for u in items:
        if u==expected or slug in u or any(c and c in u for c in candidates):
            if u not in out: out.append(u)
    return out[:20]
rows=db.get('cms_rows') or []
stored=[str(x.get('url') or '') for x in rows]
local=locs(read(localp)); live=locs(read(livep))
page=read(pagep)
can=''
for tag in re.findall(r'<link\b[^>]*>',page,re.I|re.S):
    rel=re.search(r'\brel\s*=\s*["\']([^"\']*)["\']',tag,re.I|re.S)
    if rel and 'canonical' in rel.group(1).lower().split():
        h=re.search(r'\bhref\s*=\s*["\']([^"\']*)["\']',tag,re.I|re.S)
        can=html.unescape(h.group(1).strip()) if h else ''
        break
verify_raw=''
verify_json=None
if verifyp:
    verify_raw=read(verifyp)
    try: verify_json=json.loads(verify_raw)
    except Exception: verify_json={'unparseable':True,'raw_excerpt':verify_raw[:1000]}
log_excerpt=[]
if logp:
    for line in read(logp).splitlines():
        if 'sitemap' in line.lower() or 'seo_verify' in line.lower() or 'cms_id=94' in line:
            log_excerpt.append(line[:1000])
result={
 'task':'diagnose_cf50_021_sitemap_url_v1','read_only':True,'cms_id':94,
 'expected_canonical_url':expected,'live_page_canonical':can,
 'cms_rows':rows,'share_index_rows':db.get('share_index_rows') or [],
 'local_sitemap_exists':pathlib.Path(localp).is_file(),
 'local_sitemap_expected_member':expected in local,
 'live_sitemap_expected_member':expected in live,
 'local_relevant_locs':relevant(local,stored),
 'live_relevant_locs':relevant(live,stored),
 'verification_file':pathlib.Path(verifyp).name if verifyp else '',
 'verification_json':verify_json,
 'latest_publisher_log':pathlib.Path(logp).name if logp else '',
 'publisher_log_relevant_excerpt':log_excerpt[-30:],
 'cms_write_attempted':False,'cron_mutated':False,'queue_consumed':False,
}
# Evidence classification only; no repair is performed here.
result['stored_url_differs_from_canonical']=any((x.get('url') or '').strip() and (x.get('url') or '').strip()!=expected for x in rows)
result['root_cause_candidate']='cms_stored_url_selected_by_sitemap_generator' if result['stored_url_differs_from_canonical'] and not result['live_sitemap_expected_member'] else 'UNPROVEN'
json.dump(result,open(out,'w',encoding='utf-8'),ensure_ascii=False,indent=2,sort_keys=True)
open(out,'a').write('\n')
PY

echo DIAGNOSE_CF50_021_SITEMAP_URL_V1=PASS
