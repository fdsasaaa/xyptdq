#!/bin/bash
# Read-only diagnostic for the V3 SEO文章 -> tzjq consolidation DB precondition.
set -euo pipefail
umask 077
RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
[ -n "$RESULT_FILE" ] || exit 2
[ -f "$WEBROOT/config/database.php" ] || exit 3
TMP="$(mktemp /tmp/xyptdq-v3-precondition.XXXXXX.php)"
trap 'rm -f "$TMP"' EXIT
cat > "$TMP" <<'PHP'
<?php
$db=[]; require $argv[1]; $c=$db['default']??[]; $p=$c['DBPrefix']??'dr_';
if(!preg_match('/^[A-Za-z0-9_]+$/',$p)) exit(20);
$database=(string)$c['database'];
$pdo=new PDO('mysql:host='.$c['hostname'].';dbname='.$database.';charset=utf8mb4',$c['username'],$c['password'],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC]);
$cat=$p.'1_share_category'; $news=$p.'1_news'; $idx=$p.'1_news_index'; $hits=$p.'1_news_hits'; $share=$p.'1_share_index';
$out=['task'=>'diagnose_v3_db_precondition','production_writes'=>false,'article_publishing'=>false];
$out['categories']=$pdo->query("SELECT id,name,dirname,mid,disabled,`show` AS show_flag FROM `$cat` WHERE id IN (3,7) ORDER BY id")->fetchAll();
$out['catid7_total']=(int)$pdo->query("SELECT COUNT(*) FROM `$news` WHERE catid=7")->fetchColumn();
$ids=[85,86,88,91]; $rows=[];
foreach($ids as $id){
 $n=$pdo->prepare("SELECT id,catid,status,title,tableid FROM `$news` WHERE id=? LIMIT 1"); $n->execute([$id]); $r=$n->fetch()?:null;
 $item=['id'=>$id,'main'=>$r];
 if($r){$tid=(int)$r['tableid'];$data=$p.'1_news_data_'.$tid;$d=$pdo->prepare("SELECT catid FROM `$data` WHERE id=? LIMIT 1");$d->execute([$id]);$v=$d->fetchColumn();$item['data_catid']=$v===false?null:(int)$v;}
 $q=$pdo->prepare("SELECT status FROM `$idx` WHERE id=? LIMIT 1");$q->execute([$id]);$v=$q->fetchColumn();$item['news_index_status']=$v===false?null:(int)$v;
 $q=$pdo->prepare("SELECT mid FROM `$share` WHERE id=? LIMIT 1");$q->execute([$id]);$v=$q->fetchColumn();$item['share_index_mid']=$v===false?null:(string)$v;
 $q=$pdo->prepare("SELECT COUNT(*) FROM `$hits` WHERE id=?");$q->execute([$id]);$item['hits_count']=(int)$q->fetchColumn();
 $rows[]=$item;
}
$out['articles']=$rows;
$tables=$pdo->query("SELECT table_name FROM information_schema.tables WHERE table_schema=".$pdo->quote($database)." AND table_name LIKE ".$pdo->quote($p.'1_%_index')." ORDER BY table_name")->fetchAll(PDO::FETCH_COLUMN);
$collisions=[];foreach($tables as $t){if($t===$idx||$t===$share)continue;if(!preg_match('/^[A-Za-z0-9_]+$/',$t))continue;$q=$pdo->query("SELECT id FROM `$t` WHERE id IN (85,86) ORDER BY id")->fetchAll(PDO::FETCH_COLUMN);foreach($q as $id)$collisions[]=['table'=>$t,'id'=>(int)$id];}
$out['cross_module_collisions_85_86']=$collisions;
$cols=$pdo->prepare("SELECT column_name,column_type,is_nullable,column_default,extra FROM information_schema.columns WHERE table_schema=? AND table_name=? ORDER BY ordinal_position");$cols->execute([$database,$hits]);$schema=$cols->fetchAll();$out['hits_schema']=$schema;
$unsafe=[];foreach($schema as $col){$name=(string)$col['column_name'];if($name==='id')continue;$extra=strtolower((string)$col['extra']);if((string)$col['is_nullable']==='NO'&&$col['column_default']===null&&strpos($extra,'auto_increment')===false&&strpos($extra,'generated')===false)$unsafe[]=$name;}
$out['hits_id_only_insert_unsafe_columns']=$unsafe;
foreach([88,91] as $id){$q=$pdo->prepare("SELECT * FROM `$hits` WHERE id=? LIMIT 1");$q->execute([$id]);$out['sample_hits_rows'][(string)$id]=$q->fetch()?:null;}
file_put_contents($argv[2],json_encode($out,JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES|JSON_PRETTY_PRINT)."\n");
PHP
php "$TMP" "$WEBROOT/config/database.php" "$RESULT_FILE"
echo "V3_DB_PRECONDITION_DIAGNOSTIC=PASS"
