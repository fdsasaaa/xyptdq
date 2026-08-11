#!/bin/bash
set -euo pipefail
umask 077
RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
CANONICAL="https://www.laocaimi.org"
PHASE="init"
[ -n "$RESULT_FILE" ] || exit 2
[ -f "$WEBROOT/config/database.php" ] || exit 3
TMP="$(mktemp -d /tmp/xyptdq-seo-articles-diagnose.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

write_error(){
  python3 - "$RESULT_FILE" "$PHASE" "$1" <<'PY'
import json,sys
out,phase,rc=sys.argv[1:]
p={"task":"diagnose_seo_articles_consolidation_v1","diagnostic_status":"BLOCKED","phase":phase,"task_exit_code":int(rc),"blocking_item":"runtime_error","production_writes":False,"article_publishing":False,"secrets_disclosed":False}
with open(out,'w',encoding='utf-8') as f: json.dump(p,f,ensure_ascii=False,indent=2,sort_keys=True); f.write('\n')
PY
}
on_err(){ rc=$?; trap - ERR; write_error "$rc" || true; exit "$rc"; }
trap on_err ERR

PHASE="db_inventory"
cat > "$TMP/inventory.php" <<'PHP'
<?php
$db=[]; require $argv[1];
$c=$db['default']??[]; $prefix=$c['DBPrefix']??'dr_';
if(!preg_match('/^[A-Za-z0-9_]+$/',$prefix)) exit(10);
$pdo=new PDO('mysql:host='.$c['hostname'].';dbname='.$c['database'].';charset=utf8mb4',$c['username'],$c['password'],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC]);
$cat=$prefix.'1_share_category'; $news=$prefix.'1_news'; $share=$prefix.'1_share_index';
$cats=[];
foreach([3,7] as $cid){$st=$pdo->prepare("SELECT id,name,dirname,mid,disabled,`show` AS show_flag FROM `$cat` WHERE id=? LIMIT 1");$st->execute([$cid]);$cats[(string)$cid]=$st->fetch()?:null;}
$rows=$pdo->query("SELECT id,catid,status,title,tableid,updatetime FROM `$news` WHERE id IN (85,86,88,91) ORDER BY id")->fetchAll();
$out=[];
foreach($rows as $r){
  $id=(int)$r['id']; $tid=(int)$r['tableid']; $dataTable=$prefix.'1_news_data_'.$tid;
  $dataExists=false; $dataCatid=null;
  if(preg_match('/^[A-Za-z0-9_]+$/',$dataTable)){
    $st=$pdo->prepare("SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=DATABASE() AND table_name=?");$st->execute([$dataTable]);$dataExists=((int)$st->fetchColumn()===1);
    if($dataExists){$st=$pdo->prepare("SELECT catid FROM `$dataTable` WHERE id=? LIMIT 1");$st->execute([$id]);$v=$st->fetchColumn();$dataCatid=$v===false?null:(int)$v;}
  }
  $st=$pdo->prepare("SELECT id,mid FROM `$share` WHERE id=? LIMIT 1");$st->execute([$id]);$shareRow=$st->fetch()?:null;
  $out[]=[
    'id'=>$id,'title'=>(string)$r['title'],'catid'=>(int)$r['catid'],'status'=>(int)$r['status'],'tableid'=>$tid,'updatetime'=>(int)$r['updatetime'],
    'data_table'=>$dataTable,'data_table_exists'=>$dataExists,'data_catid'=>$dataCatid,
    'share_index'=>$shareRow?['id'=>(int)$shareRow['id'],'mid'=>(string)$shareRow['mid']]:null
  ];
}
$total7=(int)$pdo->query("SELECT COUNT(*) FROM `$news` WHERE catid=7")->fetchColumn();
echo json_encode(['categories'=>$cats,'catid7_total'=>$total7,'articles'=>$out],JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES|JSON_PRETTY_PRINT);
PHP
php "$TMP/inventory.php" "$WEBROOT/config/database.php" > "$TMP/db.json"

PHASE="http_inventory"
python3 - <<'PY' > "$TMP/http-seed.json"
import json
print(json.dumps({"articles":{}},ensure_ascii=False))
PY
for id in 85 86 88 91; do
  code=$(curl -sk --max-time 30 -o "$TMP/article-$id.html" -w '%{http_code}' "$CANONICAL/index.php?c=show&id=$id" || true)
  location=$(curl -skI --max-time 30 "$CANONICAL/index.php?c=show&id=$id" | awk 'BEGIN{IGNORECASE=1}/^Location:/{sub(/\r$/,"");sub(/^[^:]*:[[:space:]]*/,"");print;exit}' || true)
  canonical=$(python3 - "$TMP/article-$id.html" <<'PY'
import html,re,sys
s=open(sys.argv[1],encoding='utf-8',errors='ignore').read()
for tag in re.findall(r'<link\b[^>]*>',s,re.I|re.S):
 r=re.search(r'\brel\s*=\s*["\']([^"\']*)["\']',tag,re.I|re.S)
 if r and 'canonical' in html.unescape(r.group(1)).lower().split():
  h=re.search(r'\bhref\s*=\s*["\']([^"\']*)["\']',tag,re.I|re.S);print(html.unescape(h.group(1)).strip() if h else '');break
PY
)
  python3 - "$TMP/http-seed.json" "$id" "$code" "$location" "$canonical" <<'PY'
import json,sys
p,id_,code,loc,can=sys.argv[1:]; d=json.load(open(p)); d['articles'][id_]={'http_status':int(code) if code.isdigit() else 0,'location':loc,'canonical':can}; json.dump(d,open(p,'w'),ensure_ascii=False,indent=2,sort_keys=True)
PY
done

PHASE="final"
python3 - "$TMP/db.json" "$TMP/http-seed.json" "$RESULT_FILE" <<'PY'
import json,sys
db=json.load(open(sys.argv[1],encoding='utf-8')); http=json.load(open(sys.argv[2],encoding='utf-8'))
expected_titles={85:'2026年最新信誉平台排行榜与评测',86:'平台安全防护措施详解：从注册到使用',88:'分分彩投注技巧：先看命中率、奖金与资金风险',91:'分分彩投注技巧：先算命中率、单期成本还是返奖？'}
mm=[]
c3=db['categories'].get('3'); c7=db['categories'].get('7')
if not c3: mm.append('category3_missing')
else:
 for k,v in [('name','投注机巧'),('dirname','tzjq'),('mid','news')]:
  if str(c3.get(k,''))!=v: mm.append(f'category3_{k}={c3.get(k)!r}')
 if int(c3.get('disabled',-1))!=0: mm.append('category3_disabled_not_0')
 if int(c3.get('show_flag',-1))!=1: mm.append('category3_show_not_1')
if not c7: mm.append('category7_missing')
else:
 for k,v in [('name','SEO文章'),('dirname','seo-articles'),('mid','news')]:
  if str(c7.get(k,''))!=v: mm.append(f'category7_{k}={c7.get(k)!r}')
 if int(c7.get('disabled',-1))!=0: mm.append('category7_disabled_not_0')
 if int(c7.get('show_flag',-1))!=1: mm.append('category7_show_not_1')
if db.get('catid7_total')!=4: mm.append(f'catid7_total={db.get("catid7_total")}')
seen=set()
for a in db['articles']:
 i=int(a['id']);seen.add(i)
 if i not in expected_titles: mm.append(f'unexpected_article_{i}');continue
 if a['title']!=expected_titles[i]: mm.append(f'article{i}_title_mismatch')
 if a['catid']!=7: mm.append(f'article{i}_catid={a["catid"]}')
 if a['status']!=9: mm.append(f'article{i}_status={a["status"]}')
 if not a['data_table_exists']: mm.append(f'article{i}_data_table_missing')
 if a['data_catid']!=7: mm.append(f'article{i}_data_catid={a["data_catid"]}')
 si=a.get('share_index')
 if not si: mm.append(f'article{i}_share_index_missing')
 elif si.get('mid')!='news': mm.append(f'article{i}_share_mid={si.get("mid")!r}')
for i in expected_titles:
 if i not in seen: mm.append(f'article{i}_main_row_missing')
p={"task":"diagnose_seo_articles_consolidation_v1","diagnostic_status":"COMPLETE","phase":"final","db":db,"http":http,"v1_precondition_mismatches":mm,"blocking_item":"NONE","production_writes":False,"article_publishing":False,"secrets_disclosed":False}
with open(sys.argv[3],'w',encoding='utf-8') as f:json.dump(p,f,ensure_ascii=False,indent=2,sort_keys=True);f.write('\n')
PY
trap - ERR
