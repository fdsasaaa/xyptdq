#!/bin/bash
set -euo pipefail
umask 077
RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
[ -n "$RESULT_FILE" ] || exit 2
[ -f "$WEBROOT/config/database.php" ] || exit 3
TMP="$(mktemp -d /tmp/xyptdq-seo-articles-v2diag.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/diag.php" <<'PHP'
<?php
$db=[];require $argv[1];$c=$db['default'];$prefix=$c['DBPrefix']??'dr_';
if(!preg_match('/^[A-Za-z0-9_]+$/',$prefix))exit(10);
$pdo=new PDO('mysql:host='.$c['hostname'].';dbname='.$c['database'].';charset=utf8mb4',$c['username'],$c['password'],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC]);
$database=(string)$c['database'];$news=$prefix.'1_news';$newsIndex=$prefix.'1_news_index';$hits=$prefix.'1_news_hits';$share=$prefix.'1_share_index';
$out=[];
foreach([85,86,88,91] as $id){
 $st=$pdo->prepare("SELECT id,catid,status,title,tableid FROM `$news` WHERE id=? LIMIT 1");$st->execute([$id]);$main=$st->fetch()?:null;
 $st=$pdo->prepare("SELECT * FROM `$newsIndex` WHERE id=? LIMIT 1");$st->execute([$id]);$index=$st->fetch()?:null;
 $st=$pdo->prepare("SELECT * FROM `$hits` WHERE id=? LIMIT 1");$st->execute([$id]);$hit=$st->fetch()?:null;
 $st=$pdo->prepare("SELECT id,mid FROM `$share` WHERE id=? LIMIT 1");$st->execute([$id]);$shared=$st->fetch()?:null;
 $out[(string)$id]=['main'=>$main,'news_index'=>$index,'hits'=>$hit,'share_index'=>$shared];
}
$tables=$pdo->query("SELECT table_name FROM information_schema.tables WHERE table_schema=".$pdo->quote($database)." AND table_name LIKE ".$pdo->quote($prefix.'1_%_index')." ORDER BY table_name")->fetchAll(PDO::FETCH_COLUMN);
$collisions=[];
foreach($tables as $table){
 if($table===$newsIndex||$table===$share)continue;
 if(!preg_match('/^[A-Za-z0-9_]+$/',$table))continue;
 $q="SELECT id FROM `".$table."` WHERE id IN (85,86) ORDER BY id";
 foreach($pdo->query($q)->fetchAll(PDO::FETCH_COLUMN) as $id)$collisions[]=['table'=>$table,'id'=>(int)$id];
}
echo json_encode(['articles'=>$out,'cross_module_collisions_85_86'=>$collisions],JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES|JSON_PRETTY_PRINT);
PHP
php "$TMP/diag.php" "$WEBROOT/config/database.php" > "$TMP/db.json"
python3 - "$TMP/db.json" "$RESULT_FILE" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding='utf-8'))
checks={}
for sid,a in d['articles'].items():
    idx=a.get('news_index') or {}; hit=a.get('hits') or {}; sh=a.get('share_index')
    checks[sid]={
      'news_index_present':bool(a.get('news_index')),
      'news_index_status':idx.get('status'),
      'hits_present':bool(a.get('hits')),
      'share_index_mid':None if not sh else sh.get('mid')
    }
p={
 'task':'diagnose_seo_articles_consolidation_v2',
 'diagnostic_status':'COMPLETE',
 'checks':checks,
 'cross_module_collisions_85_86':d.get('cross_module_collisions_85_86',[]),
 'production_writes':False,'article_publishing':False,'secrets_disclosed':False
}
with open(sys.argv[2],'w',encoding='utf-8') as f:json.dump(p,f,ensure_ascii=False,indent=2,sort_keys=True);f.write('\n')
PY
