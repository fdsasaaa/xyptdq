#!/bin/bash
# Final rollback-gated production closure for SEO文章 (catid 7) -> 投注机巧/tzjq (catid 3).
# Production diagnostics proved IDs 85/86 are valid published news rows missing only
# dr_1_share_index and dr_1_news_hits. V4 repairs those two infrastructure rows with
# zero historical hit counts, migrates all four legacy rows, retires catid 7, deploys
# the reviewed redirect/navigation source, regenerates sitemap, and verifies live state.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
CANONICAL="https://www.laocaimi.org"
TARGET_SHA="19e2816289490f6b25e581716d30af5e8bb5fe5d"
PHASE="init"
DEPLOY="NO"; DB="NO"; ROLLBACK="NO"; SHARE="NO"; HITS="NO"; RETIRED="NO"; SITEMAP="NO"
MMAIN=0; MDATA=0; MSHARE=0; MHITS=0; HTTP_OK=0; CAN_OK=0; ARTICLE_SITEMAP=0
OLD_SITEMAP=-1; TZ_SITEMAP=-1; REDIR_DIR="NO"; REDIR_ID="NO"; NAV_PC=-1; NAV_MOBILE=-1
DESC91="NO"; H1CTRL="NO"; FRAMEWORK="NO"; CATEGORY7_REMAINING=-1
ERROR_CLASS="NONE"; BLOCKER="NONE"

[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3
[ -d "$WEBROOT" ] || exit 4
[ -f "$WEBROOT/config/database.php" ] || exit 5
TMP="$(mktemp -d /tmp/xyptdq-seo-consolidate-v4.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

emit() {
  local status="$1"
  python3 - "$RESULT_FILE" "$status" "$PHASE" "$TARGET_SHA" "$DEPLOY" "$DB" "$ROLLBACK" "$SHARE" "$HITS" "$RETIRED" "$SITEMAP" "$MMAIN" "$MDATA" "$MSHARE" "$MHITS" "$HTTP_OK" "$CAN_OK" "$ARTICLE_SITEMAP" "$OLD_SITEMAP" "$TZ_SITEMAP" "$REDIR_DIR" "$REDIR_ID" "$NAV_PC" "$NAV_MOBILE" "$DESC91" "$H1CTRL" "$FRAMEWORK" "$CATEGORY7_REMAINING" "$ERROR_CLASS" "$BLOCKER" <<'PY'
import json,sys
(out,status,phase,target,deploy,db,rollback,share,hits,retired,sitemap,mm,md,ms,mh,http,can,arts,olds,tzs,rdir,rid,npc,nmob,desc,h1,framework,c7,error,blocker)=sys.argv[1:]
p={
  'task':'consolidate_seo_articles_into_tzjq_v4',
  'deployment_status':status,
  'phase':phase,
  'target_sha':target,
  'deploy':deploy,
  'db_migration':db,
  'rollback':rollback,
  'share_index_repair':share,
  'hits_repair':hits,
  'legacy_category_retired':retired,
  'sitemap_regenerated':sitemap,
  'migrated_main_rows':int(mm),
  'migrated_data_rows':int(md),
  'repaired_share_index_rows':int(ms),
  'repaired_hits_rows':int(mh),
  'repaired_ids':[85,86] if int(ms)==2 and int(mh)==2 else [],
  'article_http_200_count':int(http),
  'article_self_canonical_count':int(can),
  'sitemap_migrated_article_count':int(arts),
  'sitemap_old_category_count':int(olds),
  'sitemap_tzjq_count':int(tzs),
  'old_dir_route_301_to_tzjq':rdir,
  'old_id_route_301_to_tzjq':rid,
  'pc_old_nav_link_count':int(npc),
  'mobile_old_nav_link_count':int(nmob),
  'article91_description_unchanged':desc,
  'h1_controls_74_75':h1,
  'framework_integrity':framework,
  'category7_remaining_articles':int(c7),
  'deploy_error_class':error,
  'blocking_item':blocker,
  'article_publishing_attempted':False,
  'publisher_cron_changed':False,
  'scheduled_queue_consumed':False,
  'secrets_disclosed':False,
}
with open(out,'w',encoding='utf-8') as f:
    json.dump(p,f,ensure_ascii=False,indent=2,sort_keys=True); f.write('\n')
PY
}

canonical_from_file() {
  python3 - "$1" <<'PY'
import html,re,sys
s=open(sys.argv[1],encoding='utf-8',errors='ignore').read()
for tag in re.findall(r'<link\b[^>]*>',s,re.I|re.S):
    rel=re.search(r'\brel\s*=\s*["\']([^"\']*)["\']',tag,re.I|re.S)
    if rel and 'canonical' in html.unescape(rel.group(1)).lower().split():
        href=re.search(r'\bhref\s*=\s*["\']([^"\']*)["\']',tag,re.I|re.S)
        print(html.unescape(href.group(1)).strip() if href else '')
        break
PY
}

description_from_file() {
  python3 - "$1" <<'PY'
import html,re,sys
s=open(sys.argv[1],encoding='utf-8',errors='ignore').read()
for tag in re.findall(r'<meta\b[^>]*>',s,re.I|re.S):
    name=re.search(r'\bname\s*=\s*["\']([^"\']*)["\']',tag,re.I|re.S)
    if name and html.unescape(name.group(1)).strip().lower()=='description':
        content=re.search(r'\bcontent\s*=\s*["\']([^"\']*)["\']',tag,re.I|re.S)
        print(html.unescape(content.group(1)).strip() if content else '')
        break
PY
}

h1_from_file() {
  python3 - "$1" <<'PY'
import html,re,sys
s=open(sys.argv[1],encoding='utf-8',errors='ignore').read()
m=re.search(r'<h1\b[^>]*>(.*?)</h1\s*>',s,re.I|re.S)
if m: print(' '.join(html.unescape(re.sub(r'<[^>]+>',' ',m.group(1))).split()))
PY
}

rollback() {
  set +e
  if [ -s "$TMP/before.json" ]; then
    cat > "$TMP/restore.php" <<'PHP'
<?php
$db=[];require $argv[1];$s=json_decode(file_get_contents($argv[2]),true);$c=$db['default']??[];$p=$c['DBPrefix']??'dr_';
if(!preg_match('/^[A-Za-z0-9_]+$/',$p))exit(20);
$pdo=new PDO('mysql:host='.$c['hostname'].';dbname='.$c['database'].';charset=utf8mb4',$c['username'],$c['password'],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_EMULATE_PREPARES=>false]);
$news=$p.'1_news';$cat=$p.'1_share_category';$share=$p.'1_share_index';$hits=$p.'1_news_hits';
$pdo->beginTransaction();
try{
  foreach($s['rows'] as $r){
    $id=(int)$r['id'];$tid=(int)$r['tableid'];$data=$p.'1_news_data_'.$tid;
    if(!preg_match('/^[A-Za-z0-9_]+$/',$data))throw new RuntimeException('unsafe data table');
    $q=$pdo->prepare("UPDATE `$news` SET catid=? WHERE id=?");$q->execute([(int)$r['catid'],$id]);
    $q=$pdo->prepare("UPDATE `$data` SET catid=? WHERE id=?");$q->execute([(int)$r['data_catid'],$id]);
  }
  $c7=$s['category7'];$q=$pdo->prepare("UPDATE `$cat` SET disabled=?,`show`=? WHERE id=7 AND dirname='seo-articles'");$q->execute([(int)$c7['disabled'],(int)$c7['show_flag']]);
  $pdo->exec("DELETE FROM `$share` WHERE id IN (85,86) AND mid='news'");
  $pdo->exec("DELETE FROM `$hits` WHERE id IN (85,86)");
  $pdo->commit();
}catch(Throwable $e){if($pdo->inTransaction())$pdo->rollBack();exit(21);}
PHP
    php "$TMP/restore.php" "$WEBROOT/config/database.php" "$TMP/before.json" >/dev/null 2>&1 && ROLLBACK="YES"
  fi
  [ ! -f "$TMP/index.before" ] || { cp "$TMP/index.before" "$WEBROOT/index.php"; ROLLBACK="YES"; }
  [ ! -f "$TMP/pc.before" ] || { cp "$TMP/pc.before" "$WEBROOT/template/pc/default/home/seo_header.html"; ROLLBACK="YES"; }
  [ ! -f "$TMP/mobile.before" ] || { cp "$TMP/mobile.before" "$WEBROOT/template/mobile/default/home/seo_header.html"; ROLLBACK="YES"; }
  if [ -f "$TMP/sitemap.before" ]; then cp "$TMP/sitemap.before" "$WEBROOT/sitemap.xml"; elif [ -f "$WEBROOT/sitemap.xml" ]; then rm -f "$WEBROOT/sitemap.xml"; fi
  set -e
}

block() {
  BLOCKER="$1"
  if [ -s "$TMP/before.json" ] && { [ "$DB" = "PASS" ] || [ "$DEPLOY" = "PASS" ]; }; then rollback; fi
  emit BLOCKED
  echo "[seo-consolidate-v4] BLOCKED $BLOCKER class=$ERROR_CLASS phase=$PHASE" >&2
  exit 1
}

onerr() {
  rc=$?; trap - ERR
  ERROR_CLASS="unhandled_runtime_error"; BLOCKER="phase_${PHASE}_exit_${rc}"
  if [ -s "$TMP/before.json" ] && { [ "$DB" = "PASS" ] || [ "$DEPLOY" = "PASS" ]; }; then rollback; fi
  emit BLOCKED || true
  exit "$rc"
}
trap onerr ERR

PHASE="repo_sync"
cd "$REPO"
git fetch --prune origin >/dev/null 2>&1
git merge-base --is-ancestor "$TARGET_SHA" origin/main || { ERROR_CLASS="target_not_in_main"; block target_not_in_main; }

PHASE="source_verify"
python3 - "$REPO" "$TARGET_SHA" <<'PY'
import json,subprocess,sys
repo,sha=sys.argv[1:]
def show(path): return subprocess.check_output(['git','-C',repo,'show',f'{sha}:{path}'],text=True)
cm=json.loads(show('config/content_category_map.json'))
pp=json.loads(show('config/content_publication_policy.json'))
assert 'seo-articles' not in cm.get('categories',{})
assert cm.get('policy',{}).get('seo_article_category_key')=='tzjq'
assert 'seo-articles' in cm.get('policy',{}).get('retired_category_keys',[])
assert pp.get('publishing_enabled') is False
idx=show('site/index.php')
assert "seo-articles" in idx and "c=category&dir=tzjq" in idx and "true, 301" in idx
for path in ['site/template/pc/default/home/seo_header.html','site/template/mobile/default/home/seo_header.html']:
    x=show(path)
    assert '/index.php?c=category&dir=seo-articles' not in x
    assert '/index.php?c=category&dir=tzjq' in x
PY

PHASE="db_precondition"
cat > "$TMP/pre.php" <<'PHP'
<?php
$db=[];require $argv[1];$c=$db['default']??[];$p=$c['DBPrefix']??'dr_';if(!preg_match('/^[A-Za-z0-9_]+$/',$p))exit(30);
$database=(string)$c['database'];$pdo=new PDO('mysql:host='.$c['hostname'].';dbname='.$database.';charset=utf8mb4',$c['username'],$c['password'],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC,PDO::ATTR_EMULATE_PREPARES=>false]);
$cat=$p.'1_share_category';$news=$p.'1_news';$idx=$p.'1_news_index';$hits=$p.'1_news_hits';$share=$p.'1_share_index';
$c3=$pdo->query("SELECT id,name,dirname,mid,disabled,`show` AS show_flag FROM `$cat` WHERE id=3 LIMIT 1")->fetch();
$c7=$pdo->query("SELECT id,name,dirname,mid,disabled,`show` AS show_flag FROM `$cat` WHERE id=7 LIMIT 1")->fetch();
if(!$c3||$c3['name']!=='投注机巧'||$c3['dirname']!=='tzjq'||$c3['mid']!=='news'||(int)$c3['disabled']!==0||(int)$c3['show_flag']!==1)exit(31);
if(!$c7||$c7['name']!=='SEO文章'||$c7['dirname']!=='seo-articles'||$c7['mid']!=='news'||(int)$c7['disabled']!==0||(int)$c7['show_flag']!==1)exit(32);
$expected=[85=>'2026年最新信誉平台排行榜与评测',86=>'平台安全防护措施详解：从注册到使用',88=>'分分彩投注技巧：先看命中率、奖金与资金风险',91=>'分分彩投注技巧：先算命中率、单期成本还是返奖？'];
$rows=$pdo->query("SELECT id,catid,status,title,tableid,updatetime FROM `$news` WHERE id IN (85,86,88,91) ORDER BY id")->fetchAll();
if(count($rows)!==4||(int)$pdo->query("SELECT COUNT(*) FROM `$news` WHERE catid=7")->fetchColumn()!==4)exit(33);
foreach($rows as &$r){
  $id=(int)$r['id'];if(!isset($expected[$id])||$r['title']!==$expected[$id]||(int)$r['catid']!==7||(int)$r['status']!==9||(int)$r['updatetime']<=0)exit(34);
  $tid=(int)$r['tableid'];$data=$p.'1_news_data_'.$tid;if($tid<0||$tid>9999||!preg_match('/^[A-Za-z0-9_]+$/',$data))exit(35);
  $q=$pdo->prepare("SELECT catid FROM `$data` WHERE id=? LIMIT 1");$q->execute([$id]);$v=$q->fetchColumn();if($v===false||(int)$v!==7)exit(36);$r['data_catid']=(int)$v;
  $q=$pdo->prepare("SELECT status FROM `$idx` WHERE id=? LIMIT 1");$q->execute([$id]);$v=$q->fetchColumn();if($v===false||(int)$v!==9)exit(37);
  $q=$pdo->prepare("SELECT mid FROM `$share` WHERE id=? LIMIT 1");$q->execute([$id]);$mid=$q->fetchColumn();
  $q=$pdo->prepare("SELECT COUNT(*) FROM `$hits` WHERE id=?");$q->execute([$id]);$hc=(int)$q->fetchColumn();
  if(in_array($id,[85,86],true)){if($mid!==false||$hc!==0)exit(38);}else{if($mid!=='news'||$hc!==1)exit(39);}
}
unset($r);
$cols=$pdo->prepare("SELECT column_name,column_type,is_nullable,column_default,extra FROM information_schema.columns WHERE table_schema=? AND table_name=? ORDER BY ordinal_position");$cols->execute([$database,$hits]);$schema=$cols->fetchAll();
$names=array_map(fn($x)=>(string)$x['column_name'],$schema);
$required=['id','hits','day_hits','week_hits','month_hits','year_hits','day_time','week_time','month_time','year_time'];
if($names!==$required)exit(40);
foreach($schema as $col){if((string)$col['is_nullable']!=='NO'||$col['column_default']!==null||(string)$col['extra']!=='')exit(41);}
$tables=$pdo->query("SELECT table_name FROM information_schema.tables WHERE table_schema=".$pdo->quote($database)." AND table_name LIKE ".$pdo->quote($p.'1_%_index')." ORDER BY table_name")->fetchAll(PDO::FETCH_COLUMN);
foreach($tables as $t){if($t===$idx||$t===$share)continue;if(!preg_match('/^[A-Za-z0-9_]+$/',$t))continue;$q=$pdo->query("SELECT COUNT(*) FROM `$t` WHERE id IN (85,86)");if((int)$q->fetchColumn()>0)exit(42);}
echo json_encode(['category7'=>$c7,'rows'=>$rows,'hits_schema'=>$names],JSON_UNESCAPED_UNICODE|JSON_PRETTY_PRINT|JSON_UNESCAPED_SLASHES);
PHP
php "$TMP/pre.php" "$WEBROOT/config/database.php" > "$TMP/before.json" || { ERROR_CLASS="db_precondition_mismatch"; block db_precondition_mismatch; }

PHASE="http_precondition"
for id in 85 86; do
  code=$(curl -skL --max-time 30 -o "$TMP/$id.before" -w '%{http_code}' "$CANONICAL/index.php?c=show&id=$id")
  [ "$code" = "404" ] || { ERROR_CLASS="unroutable_baseline_changed"; block "article_${id}_baseline_not_404"; }
done
for id in 88 91; do
  code=$(curl -skL --max-time 30 -o "$TMP/$id.before" -w '%{http_code}' "$CANONICAL/index.php?c=show&id=$id")
  [ "$code" = "200" ] || { ERROR_CLASS="live_baseline_changed"; block "article_${id}_baseline_not_200"; }
  [ "$(canonical_from_file "$TMP/$id.before")" = "$CANONICAL/index.php?c=show&id=$id" ] || { ERROR_CLASS="canonical_baseline_changed"; block "article_${id}_canonical_changed"; }
done
DESC91_BEFORE="$(description_from_file "$TMP/91.before")"
[ -n "$DESC91_BEFORE" ] || { ERROR_CLASS="description_baseline_missing"; block article91_description_missing; }

PHASE="snapshot"
cp "$WEBROOT/index.php" "$TMP/index.before"
cp "$WEBROOT/template/pc/default/home/seo_header.html" "$TMP/pc.before"
cp "$WEBROOT/template/mobile/default/home/seo_header.html" "$TMP/mobile.before"
[ ! -f "$WEBROOT/sitemap.xml" ] || cp "$WEBROOT/sitemap.xml" "$TMP/sitemap.before"

git show "$TARGET_SHA:site/index.php" > "$TMP/index.source"
git show "$TARGET_SHA:site/template/pc/default/home/seo_header.html" > "$TMP/pc.source"
git show "$TARGET_SHA:site/template/mobile/default/home/seo_header.html" > "$TMP/mobile.source"
[ -s "$TMP/index.source" ] && [ -s "$TMP/pc.source" ] && [ -s "$TMP/mobile.source" ] || { ERROR_CLASS="source_export_failed"; block source_export_failed; }

PHASE="db_migration"
cat > "$TMP/migrate.php" <<'PHP'
<?php
$db=[];require $argv[1];$before=json_decode(file_get_contents($argv[2]),true);$c=$db['default']??[];$p=$c['DBPrefix']??'dr_';if(!preg_match('/^[A-Za-z0-9_]+$/',$p))exit(50);
$pdo=new PDO('mysql:host='.$c['hostname'].';dbname='.$c['database'].';charset=utf8mb4',$c['username'],$c['password'],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_EMULATE_PREPARES=>false]);
$news=$p.'1_news';$cat=$p.'1_share_category';$share=$p.'1_share_index';$hits=$p.'1_news_hits';$counts=['main'=>0,'data'=>0,'share'=>0,'hits'=>0];
$pdo->beginTransaction();
try{
  $byId=[];foreach($before['rows'] as $r)$byId[(int)$r['id']]=$r;
  foreach([85,86] as $id){
    if(!isset($byId[$id]))throw new RuntimeException('missing baseline row');
    $stamp=max(1,(int)$byId[$id]['updatetime']);
    $q=$pdo->prepare("INSERT INTO `$hits` (id,hits,day_hits,week_hits,month_hits,year_hits,day_time,week_time,month_time,year_time) VALUES (?,0,0,0,0,0,?,?,?,?,?)");
    $q->execute([$id,$stamp,$stamp,$stamp,$stamp]);$counts['hits']+=$q->rowCount();
    $q=$pdo->prepare("INSERT INTO `$share` (id,mid) VALUES (?,'news')");$q->execute([$id]);$counts['share']+=$q->rowCount();
  }
  foreach([85,86,88,91] as $id){
    $r=$byId[$id];$tid=(int)$r['tableid'];$data=$p.'1_news_data_'.$tid;if(!preg_match('/^[A-Za-z0-9_]+$/',$data))throw new RuntimeException('unsafe data table');
    $q=$pdo->prepare("UPDATE `$news` SET catid=3 WHERE id=? AND catid=7");$q->execute([$id]);$counts['main']+=$q->rowCount();
    $q=$pdo->prepare("UPDATE `$data` SET catid=3 WHERE id=? AND catid=7");$q->execute([$id]);$counts['data']+=$q->rowCount();
  }
  $q=$pdo->prepare("UPDATE `$cat` SET disabled=1,`show`=0 WHERE id=7 AND dirname='seo-articles' AND disabled=0 AND `show`=1");$q->execute();if($q->rowCount()!==1)throw new RuntimeException('category retirement rowcount');
  if($counts!==['main'=>4,'data'=>4,'share'=>2,'hits'=>2])throw new RuntimeException('unexpected rowcounts');
  $pdo->commit();
  echo json_encode($counts);
}catch(Throwable $e){if($pdo->inTransaction())$pdo->rollBack();fwrite(STDERR,$e->getMessage());exit(51);}
PHP
MIG="$(php "$TMP/migrate.php" "$WEBROOT/config/database.php" "$TMP/before.json")" || { ERROR_CLASS="db_transaction_failed"; block db_transaction_failed; }
MMAIN=$(printf '%s' "$MIG" | php -r '$x=json_decode(stream_get_contents(STDIN),true);echo (int)($x["main"]??0);')
MDATA=$(printf '%s' "$MIG" | php -r '$x=json_decode(stream_get_contents(STDIN),true);echo (int)($x["data"]??0);')
MSHARE=$(printf '%s' "$MIG" | php -r '$x=json_decode(stream_get_contents(STDIN),true);echo (int)($x["share"]??0);')
MHITS=$(printf '%s' "$MIG" | php -r '$x=json_decode(stream_get_contents(STDIN),true);echo (int)($x["hits"]??0);')
DB="PASS"; SHARE="PASS"; HITS="PASS"; RETIRED="PASS"

PHASE="deploy_source"
cp "$TMP/index.source" "$WEBROOT/index.php"
cp "$TMP/pc.source" "$WEBROOT/template/pc/default/home/seo_header.html"
cp "$TMP/mobile.source" "$WEBROOT/template/mobile/default/home/seo_header.html"
php -l "$WEBROOT/index.php" >/dev/null || { ERROR_CLASS="php_syntax_failed"; block deployed_index_php_invalid; }
DEPLOY="PASS"

PHASE="sitemap"
XYPTDQ_WEBROOT="$WEBROOT" XYPTDQ_DB_CONFIG="$WEBROOT/config/database.php" XYPTDQ_SITEMAP="$WEBROOT/sitemap.xml" php "$REPO/scripts/seo/generate_sitemap.php" >/dev/null || { ERROR_CLASS="sitemap_generation_failed"; block sitemap_generation_failed; }
SITEMAP="PASS"

PHASE="db_postverify"
POST=$(php -r '
$db=[];require $argv[1];$c=$db["default"]??[];$p=$c["DBPrefix"]??"dr_";$pdo=new PDO("mysql:host=".$c["hostname"].";dbname=".$c["database"].";charset=utf8mb4",$c["username"],$c["password"],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC]);$news=$p."1_news";$cat=$p."1_share_category";$share=$p."1_share_index";$hits=$p."1_news_hits";$rows=$pdo->query("SELECT id,catid,tableid FROM `$news` WHERE id IN (85,86,88,91) ORDER BY id")->fetchAll();$ok=count($rows)===4;$dataOk=0;foreach($rows as $r){$id=(int)$r["id"];$tid=(int)$r["tableid"];$data=$p."1_news_data_".$tid;if((int)$r["catid"]!==3)$ok=false;$q=$pdo->query("SELECT catid FROM `$data` WHERE id=$id")->fetchColumn();if((int)$q===3)$dataOk++;else$ok=false;}$s=$pdo->query("SELECT id,mid FROM `$share` WHERE id IN (85,86) ORDER BY id")->fetchAll();$h=$pdo->query("SELECT id,hits,day_hits,week_hits,month_hits,year_hits FROM `$hits` WHERE id IN (85,86) ORDER BY id")->fetchAll();$c7=$pdo->query("SELECT disabled,`show` AS s FROM `$cat` WHERE id=7 AND dirname=\"seo-articles\"")->fetch();$rem=(int)$pdo->query("SELECT COUNT(*) FROM `$news` WHERE catid=7")->fetchColumn();$ok=$ok&&$dataOk===4&&count($s)===2&&$s[0]["mid"]==="news"&&$s[1]["mid"]==="news"&&count($h)===2&&$rem===0&&(int)$c7["disabled"]===1&&(int)$c7["s"]===0;foreach($h as $r){foreach(["hits","day_hits","week_hits","month_hits","year_hits"] as $k)if((int)$r[$k]!==0)$ok=false;}echo json_encode(["ok"=>$ok,"remaining"=>$rem]);
' "$WEBROOT/config/database.php")
POST_OK=$(printf '%s' "$POST" | php -r '$x=json_decode(stream_get_contents(STDIN),true);echo !empty($x["ok"])?"1":"0";')
CATEGORY7_REMAINING=$(printf '%s' "$POST" | php -r '$x=json_decode(stream_get_contents(STDIN),true);echo (int)($x["remaining"]??-1);')
[ "$POST_OK" = "1" ] || { ERROR_CLASS="db_postverify_failed"; block db_postverify_failed; }

PHASE="http_postverify"
for id in 85 86 88 91; do
  code=$(curl -skL --max-time 30 -o "$TMP/$id.after" -w '%{http_code}' "$CANONICAL/index.php?c=show&id=$id")
  if [ "$code" = "200" ]; then HTTP_OK=$((HTTP_OK+1)); else ERROR_CLASS="article_http_failed"; block "article_${id}_http_${code}"; fi
  if [ "$(canonical_from_file "$TMP/$id.after")" = "$CANONICAL/index.php?c=show&id=$id" ]; then CAN_OK=$((CAN_OK+1)); else ERROR_CLASS="article_canonical_failed"; block "article_${id}_canonical_failed"; fi
done
DESC91_AFTER="$(description_from_file "$TMP/91.after")"
if [ "$DESC91_AFTER" = "$DESC91_BEFORE" ]; then DESC91="PASS"; else ERROR_CLASS="description_regression"; block article91_description_changed; fi

code=$(curl -sk --max-time 20 -o /dev/null -D "$TMP/old-dir.headers" -w '%{http_code}' "$CANONICAL/index.php?c=category&dir=seo-articles")
loc=$(awk 'BEGIN{IGNORECASE=1}/^Location:/{sub(/\r$/,"",$0);sub(/^[^:]*:[[:space:]]*/,"",$0);print;exit}' "$TMP/old-dir.headers")
if [ "$code" = "301" ] && [ "$loc" = "$CANONICAL/index.php?c=category&dir=tzjq" ]; then REDIR_DIR="PASS"; else ERROR_CLASS="redirect_failed"; block old_dir_redirect_failed; fi
code=$(curl -sk --max-time 20 -o /dev/null -D "$TMP/old-id.headers" -w '%{http_code}' "$CANONICAL/index.php?c=category&id=7")
loc=$(awk 'BEGIN{IGNORECASE=1}/^Location:/{sub(/\r$/,"",$0);sub(/^[^:]*:[[:space:]]*/,"",$0);print;exit}' "$TMP/old-id.headers")
if [ "$code" = "301" ] && [ "$loc" = "$CANONICAL/index.php?c=category&dir=tzjq" ]; then REDIR_ID="PASS"; else ERROR_CLASS="redirect_failed"; block old_id_redirect_failed; fi

code=$(curl -skL --max-time 30 -o "$TMP/tzjq.html" -w '%{http_code}' "$CANONICAL/index.php?c=category&dir=tzjq")
[ "$code" = "200" ] || { ERROR_CLASS="tzjq_http_failed"; block tzjq_not_200; }
[ "$(canonical_from_file "$TMP/tzjq.html")" = "$CANONICAL/index.php?c=category&dir=tzjq" ] || { ERROR_CLASS="tzjq_canonical_failed"; block tzjq_canonical_failed; }
for id in 85 86 88 91; do grep -Eq "c=show(&amp;|&)id=$id([\"'&<]|$)" "$TMP/tzjq.html" || { ERROR_CLASS="tzjq_listing_missing_article"; block "tzjq_missing_article_${id}"; }; done

curl -skL --max-time 30 -A 'Mozilla/5.0' "$CANONICAL/" -o "$TMP/home.pc"
curl -skL --max-time 30 -A 'Mozilla/5.0 (Linux; Android 13; Mobile)' "$CANONICAL/" -o "$TMP/home.mobile"
NAV_PC=$(grep -o 'seo-articles' "$TMP/home.pc" | wc -l | tr -d ' ')
NAV_MOBILE=$(grep -o 'seo-articles' "$TMP/home.mobile" | wc -l | tr -d ' ')
[ "$NAV_PC" -eq 0 ] && [ "$NAV_MOBILE" -eq 0 ] || { ERROR_CLASS="old_nav_still_live"; block old_nav_still_live; }

for pair in '74|长征（送首冲）｜软件项目' '75|长征（送首冲）｜福利资源'; do
  id=${pair%%|*}; expected=${pair#*|}; code=$(curl -skL --max-time 30 -o "$TMP/h1-$id" -w '%{http_code}' "$CANONICAL/index.php?c=show&id=$id")
  [ "$code" = "200" ] || { ERROR_CLASS="h1_control_http_failed"; block "h1_control_${id}_http_failed"; }
  [ "$(h1_from_file "$TMP/h1-$id")" = "$expected" ] || { ERROR_CLASS="h1_control_regression"; block "h1_control_${id}_changed"; }
done
H1CTRL="PASS"

PHASE="sitemap_verify"
OLD_SITEMAP=$(grep -o 'c=category&amp;dir=seo-articles' "$WEBROOT/sitemap.xml" | wc -l | tr -d ' ')
TZ_SITEMAP=$(grep -o 'c=category&amp;dir=tzjq' "$WEBROOT/sitemap.xml" | wc -l | tr -d ' ')
ARTICLE_SITEMAP=0
for id in 85 86 88 91; do if grep -Eq "c=show&amp;id=$id([<&]|$)" "$WEBROOT/sitemap.xml"; then ARTICLE_SITEMAP=$((ARTICLE_SITEMAP+1)); fi; done
[ "$OLD_SITEMAP" -eq 0 ] && [ "$TZ_SITEMAP" -ge 1 ] && [ "$ARTICLE_SITEMAP" -eq 4 ] || { ERROR_CLASS="sitemap_postverify_failed"; block sitemap_postverify_failed; }

PHASE="framework_verify"
home_code=$(curl -skL --max-time 30 -o /dev/null -w '%{http_code}' "$CANONICAL/")
[ "$home_code" = "200" ] && [ "$HTTP_OK" -eq 4 ] && [ "$CAN_OK" -eq 4 ] && [ "$H1CTRL" = "PASS" ] || { ERROR_CLASS="framework_integrity_failed"; block framework_integrity_failed; }
FRAMEWORK="PASS"

PHASE="final"
ERROR_CLASS="NONE"; BLOCKER="NONE"
emit PASS
echo "SEO_ARTICLES_TO_TZJQ_V4=PASS migrated_main=$MMAIN migrated_data=$MDATA repaired_hits=$MHITS repaired_share=$MSHARE"
