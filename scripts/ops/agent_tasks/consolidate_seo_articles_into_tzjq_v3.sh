#!/bin/bash
# Final rollback-gated consolidation of SEO文章 (catid 7) into tzjq (catid 3).
# Repairs only the proven missing routing/hits rows for IDs 85/86, using DB defaults.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
CANONICAL="https://www.laocaimi.org"
TARGET_SHA="00d691001c6b5cd369ec89afeabc39b87bc12f51"
EXPECTED_FRAME_LOCK_HEX="436f646549676e697465723732"
PHASE="init"; DEPLOY="NO"; DB="NO"; ROLLBACK="NO"; SHARE="NO"; HITS="NO"; RETIRED="NO"
MMAIN=0; MDATA=0; MSHARE=0; MHITS=0; HTTP_OK=0; CAN_OK=0; OLD_SITEMAP=-1; TZ_SITEMAP=-1; ARTICLE_SITEMAP=0
REDIR_DIR="NO"; REDIR_ID="NO"; NAV_PC=-1; NAV_MOBILE=-1; DESC91="NO"; H1CTRL="NO"; FRAMEWORK="NO"
ERROR_CLASS="NONE"; BLOCKER="NONE"

[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3
[ -d "$WEBROOT" ] || exit 4
[ -f "$WEBROOT/config/database.php" ] || exit 5
TMP="$(mktemp -d /tmp/xyptdq-seo-consolidate-v3.XXXXXX)"; trap 'rm -rf "$TMP"' EXIT

emit(){
 local status="$1"
 python3 - "$RESULT_FILE" "$status" "$PHASE" "$TARGET_SHA" "$DEPLOY" "$DB" "$ROLLBACK" "$SHARE" "$HITS" "$RETIRED" "$MMAIN" "$MDATA" "$MSHARE" "$MHITS" "$HTTP_OK" "$CAN_OK" "$OLD_SITEMAP" "$TZ_SITEMAP" "$ARTICLE_SITEMAP" "$REDIR_DIR" "$REDIR_ID" "$NAV_PC" "$NAV_MOBILE" "$DESC91" "$H1CTRL" "$FRAMEWORK" "$ERROR_CLASS" "$BLOCKER" <<'PY'
import json,sys
(a,status,phase,target,deploy,db,rollback,share,hits,retired,mm,md,ms,mh,http,can,olds,tzs,arts,rdir,rid,npc,nmob,desc,h1,framework,error,blocker)=sys.argv[1:]
p={
 'task':'consolidate_seo_articles_into_tzjq_v3','deployment_status':status,'phase':phase,'target_sha':target,
 'deploy':deploy,'db_migration':db,'rollback':rollback,'share_index_repair':share,'hits_repair':hits,
 'legacy_category_retired':retired,'migrated_main_rows':int(mm),'migrated_data_rows':int(md),
 'repaired_share_index_rows':int(ms),'repaired_hits_rows':int(mh),'repaired_ids':[85,86] if int(ms)==2 and int(mh)==2 else [],
 'article_http_200_count':int(http),'article_canonical_unchanged_count':int(can),
 'sitemap_old_category_count':int(olds),'sitemap_tzjq_count':int(tzs),'sitemap_migrated_article_count':int(arts),
 'old_dir_route_301_to_tzjq':rdir,'old_id_route_301_to_tzjq':rid,'pc_old_nav_link_count':int(npc),'mobile_old_nav_link_count':int(nmob),
 'article91_description_unchanged':desc,'h1_controls_74_75':h1,'framework_integrity':framework,
 'deploy_error_class':error,'blocking_item':blocker,
 'article_publishing_attempted':False,'publisher_cron_changed':False,'scheduled_queue_consumed':False,'secrets_disclosed':False
}
with open(a,'w',encoding='utf-8') as f: json.dump(p,f,ensure_ascii=False,indent=2,sort_keys=True); f.write('\n')
PY
}

canonical(){ python3 - "$1" <<'PY'
import html,re,sys
s=open(sys.argv[1],encoding='utf-8',errors='ignore').read()
for t in re.findall(r'<link\b[^>]*>',s,re.I|re.S):
 r=re.search(r'\brel\s*=\s*["\']([^"\']*)["\']',t,re.I|re.S)
 if r and 'canonical' in html.unescape(r.group(1)).lower().split():
  h=re.search(r'\bhref\s*=\s*["\']([^"\']*)["\']',t,re.I|re.S); print(html.unescape(h.group(1)).strip() if h else ''); break
PY
}
description(){ python3 - "$1" <<'PY'
import html,re,sys
s=open(sys.argv[1],encoding='utf-8',errors='ignore').read()
for t in re.findall(r'<meta\b[^>]*>',s,re.I|re.S):
 n=re.search(r'\bname\s*=\s*["\']([^"\']*)["\']',t,re.I|re.S)
 if n and html.unescape(n.group(1)).strip().lower()=='description':
  c=re.search(r'\bcontent\s*=\s*["\']([^"\']*)["\']',t,re.I|re.S); print(html.unescape(c.group(1)).strip() if c else ''); break
PY
}
h1(){ python3 - "$1" <<'PY'
import html,re,sys
s=open(sys.argv[1],encoding='utf-8',errors='ignore').read();m=re.search(r'<h1\b[^>]*>(.*?)</h1\s*>',s,re.I|re.S)
if m: print(' '.join(html.unescape(re.sub(r'<[^>]+>',' ',m.group(1))).split()))
PY
}

rollback(){
 set +e
 if [ "$DB" = "PASS" ] && [ -s "$TMP/before.json" ]; then
  cat > "$TMP/restore.php" <<'PHP'
<?php
$db=[];require $argv[1];$s=json_decode(file_get_contents($argv[2]),true);$c=$db['default'];$p=$c['DBPrefix']??'dr_';if(!preg_match('/^[A-Za-z0-9_]+$/',$p))exit(20);
$pdo=new PDO('mysql:host='.$c['hostname'].';dbname='.$c['database'].';charset=utf8mb4',$c['username'],$c['password'],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);$news=$p.'1_news';$cat=$p.'1_share_category';$share=$p.'1_share_index';$hits=$p.'1_news_hits';$pdo->beginTransaction();
try{foreach($s['rows'] as $r){$id=(int)$r['id'];$tid=(int)$r['tableid'];$data=$p.'1_news_data_'.$tid;if(!preg_match('/^[A-Za-z0-9_]+$/',$data))throw new RuntimeException('unsafe');$st=$pdo->prepare("UPDATE `$news` SET catid=? WHERE id=?");$st->execute([(int)$r['catid'],$id]);$st=$pdo->prepare("UPDATE `$data` SET catid=? WHERE id=?");$st->execute([(int)$r['data_catid'],$id]);}
$c7=$s['category7'];$st=$pdo->prepare("UPDATE `$cat` SET disabled=?,`show`=? WHERE id=7 AND dirname='seo-articles'");$st->execute([(int)$c7['disabled'],(int)$c7['show_flag']]);$pdo->exec("DELETE FROM `$share` WHERE id IN (85,86) AND mid='news'");$pdo->exec("DELETE FROM `$hits` WHERE id IN (85,86)");$pdo->commit();}catch(Throwable $e){if($pdo->inTransaction())$pdo->rollBack();exit(21);}
PHP
  php "$TMP/restore.php" "$WEBROOT/config/database.php" "$TMP/before.json" >/dev/null 2>&1 && ROLLBACK="YES"
 fi
 [ ! -d "$TMP/template.before" ] || { rm -rf "$WEBROOT/template"; cp -a "$TMP/template.before" "$WEBROOT/template"; ROLLBACK="YES"; }
 [ ! -f "$TMP/index.before" ] || { cp -a "$TMP/index.before" "$WEBROOT/index.php"; ROLLBACK="YES"; }
 [ ! -f "$TMP/sitemap.before" ] || cp -a "$TMP/sitemap.before" "$WEBROOT/sitemap.xml"
 chown -R www-data:www-data "$WEBROOT/template" "$WEBROOT/index.php" "$WEBROOT/sitemap.xml" 2>/dev/null || true
 set -e
}
block(){ BLOCKER="$1"; if [ "$DEPLOY" = "PASS" ] || [ "$DB" = "PASS" ]; then rollback; fi; emit BLOCKED; echo "[seo-consolidate-v3] BLOCKED $BLOCKER class=$ERROR_CLASS" >&2; exit 1; }
onerr(){ rc=$?; trap - ERR; ERROR_CLASS="unhandled_runtime_error"; BLOCKER="phase_${PHASE}_exit_${rc}"; if [ "$DEPLOY" = "PASS" ] || [ "$DB" = "PASS" ];then rollback;fi;emit BLOCKED||true;exit "$rc"; }; trap onerr ERR

PHASE="repo_sync"; cd "$REPO"; git fetch --prune origin >/dev/null 2>&1; git merge-base --is-ancestor "$TARGET_SHA" origin/main || { ERROR_CLASS="target_not_in_main";block target_not_in_main; }
PHASE="source_verify"
python3 - "$REPO" "$TARGET_SHA" <<'PY'
import json,subprocess,sys
r,s=sys.argv[1:]
def show(p):return subprocess.check_output(['git','-C',r,'show',f'{s}:{p}'],text=True)
m=json.loads(show('config/content_category_map.json'));p=json.loads(show('config/content_publication_policy.json'))
assert 'seo-articles' not in m.get('categories',{});assert m.get('policy',{}).get('seo_article_category_key')=='tzjq';assert 'seo-articles' in m.get('policy',{}).get('retired_category_keys',[]);assert p.get('publishing_enabled') is False
for f in ['site/template/pc/default/home/seo_header.html','site/template/mobile/default/home/seo_header.html']:
 x=show(f);assert '/index.php?c=category&dir=seo-articles' not in x;assert '/index.php?c=category&dir=tzjq' in x
x=show('site/index.php');assert 'seo-articles' in x and "header('Location: https://www.laocaimi.org/index.php?c=category&dir=tzjq', true, 301)" in x
PY

PHASE="db_precondition"
cat > "$TMP/pre.php" <<'PHP'
<?php
$db=[];require $argv[1];$c=$db['default'];$p=$c['DBPrefix']??'dr_';if(!preg_match('/^[A-Za-z0-9_]+$/',$p))exit(30);$database=(string)$c['database'];$pdo=new PDO('mysql:host='.$c['hostname'].';dbname='.$database.';charset=utf8mb4',$c['username'],$c['password'],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC]);
$cat=$p.'1_share_category';$news=$p.'1_news';$idx=$p.'1_news_index';$hits=$p.'1_news_hits';$share=$p.'1_share_index';
$c3=$pdo->query("SELECT id,name,dirname,mid,disabled,`show` AS show_flag FROM `$cat` WHERE id=3 LIMIT 1")->fetch();$c7=$pdo->query("SELECT id,name,dirname,mid,disabled,`show` AS show_flag FROM `$cat` WHERE id=7 LIMIT 1")->fetch();
if(!$c3||$c3['name']!=='投注机巧'||$c3['dirname']!=='tzjq'||$c3['mid']!=='news'||(int)$c3['disabled']!==0||(int)$c3['show_flag']!==1)exit(31);if(!$c7||$c7['name']!=='SEO文章'||$c7['dirname']!=='seo-articles'||$c7['mid']!=='news'||(int)$c7['disabled']!==0||(int)$c7['show_flag']!==1)exit(32);
$exp=[85=>'2026年最新信誉平台排行榜与评测',86=>'平台安全防护措施详解：从注册到使用',88=>'分分彩投注技巧：先看命中率、奖金与资金风险',91=>'分分彩投注技巧：先算命中率、单期成本还是返奖？'];$rows=$pdo->query("SELECT id,catid,status,title,tableid FROM `$news` WHERE id IN (85,86,88,91) ORDER BY id")->fetchAll();if(count($rows)!==4||(int)$pdo->query("SELECT COUNT(*) FROM `$news` WHERE catid=7")->fetchColumn()!==4)exit(33);
foreach($rows as &$r){$id=(int)$r['id'];if(!isset($exp[$id])||$r['title']!==$exp[$id]||(int)$r['catid']!==7||(int)$r['status']!==9)exit(34);$tid=(int)$r['tableid'];$data=$p.'1_news_data_'.$tid;if($tid<0||$tid>9999||!preg_match('/^[A-Za-z0-9_]+$/',$data))exit(35);$st=$pdo->prepare("SELECT catid FROM `$data` WHERE id=? LIMIT 1");$st->execute([$id]);$v=$st->fetchColumn();if($v===false||(int)$v!==7)exit(36);$r['data_catid']=(int)$v;$st=$pdo->prepare("SELECT status FROM `$idx` WHERE id=? LIMIT 1");$st->execute([$id]);if((int)$st->fetchColumn()!==9)exit(37);$st=$pdo->prepare("SELECT mid FROM `$share` WHERE id=? LIMIT 1");$st->execute([$id]);$mid=$st->fetchColumn();$st=$pdo->prepare("SELECT COUNT(*) FROM `$hits` WHERE id=?");$st->execute([$id]);$hc=(int)$st->fetchColumn();if(in_array($id,[85,86],true)){if($mid!==false||$hc!==0)exit(38);}else{if($mid!=='news'||$hc!==1)exit(39);}}
unset($r);
$tables=$pdo->query("SELECT table_name FROM information_schema.tables WHERE table_schema=".$pdo->quote($database)." AND table_name LIKE ".$pdo->quote($p.'1_%_index')." ORDER BY table_name")->fetchAll(PDO::FETCH_COLUMN);foreach($tables as $t){if($t===$idx||$t===$share)continue;if(!preg_match('/^[A-Za-z0-9_]+$/',$t))continue;if((int)$pdo->query("SELECT COUNT(*) FROM `$t` WHERE id IN (85,86)")->fetchColumn()>0)exit(40);}
$cols=$pdo->prepare("SELECT column_name,is_nullable,column_default,extra FROM information_schema.columns WHERE table_schema=? AND table_name=? ORDER BY ordinal_position");$cols->execute([$database,$hits]);$schema=$cols->fetchAll();if(!$schema)exit(41);$idSeen=false;foreach($schema as $col){$name=(string)$col['column_name'];if($name==='id'){$idSeen=true;continue;}$extra=strtolower((string)$col['extra']);if((string)$col['is_nullable']==='NO'&&$col['column_default']===null&&strpos($extra,'auto_increment')===false&&strpos($extra,'generated')===false)exit(42);}if(!$idSeen)exit(43);
echo json_encode(['category7'=>$c7,'rows'=>$rows],JSON_UNESCAPED_UNICODE|JSON_PRETTY_PRINT|JSON_UNESCAPED_SLASHES);
PHP
php "$TMP/pre.php" "$WEBROOT/config/database.php" > "$TMP/before.json" || { ERROR_CLASS="db_precondition_mismatch";block db_precondition_mismatch; }

PHASE="http_precondition"
for id in 85 86;do c=$(curl -skL --max-time 30 -o "$TMP/$id.before" -w '%{http_code}' "$CANONICAL/index.php?c=show&id=$id");[ "$c" = 404 ]||{ ERROR_CLASS="unroutable_baseline_changed";block unroutable_baseline_changed; };done
for id in 88 91;do c=$(curl -skL --max-time 30 -o "$TMP/$id.before" -w '%{http_code}' "$CANONICAL/index.php?c=show&id=$id");[ "$c" = 200 ]||{ ERROR_CLASS="live_baseline_not_200";block live_baseline_not_200; };[ "$(canonical "$TMP/$id.before")" = "$CANONICAL/index.php?c=show&id=$id" ]||{ ERROR_CLASS="live_baseline_canonical";block live_baseline_canonical; };done
D91="$(description "$TMP/91.before")";[ -n "$D91" ]||{ ERROR_CLASS="article91_description_missing";block article91_description_missing; }

PHASE="snapshot";cp -a "$WEBROOT/template" "$TMP/template.before";cp -a "$WEBROOT/index.php" "$TMP/index.before";cp -a "$WEBROOT/sitemap.xml" "$TMP/sitemap.before"
PHASE="deploy_source";git show "$TARGET_SHA:scripts/deploy_safe.sh" > "$TMP/deploy_safe.sh";chmod 700 "$TMP/deploy_safe.sh";if ! XYPTDQ_REPO_DIR="$REPO" XYPTDQ_WEBROOT="$WEBROOT" bash "$TMP/deploy_safe.sh" "$TARGET_SHA" > "$TMP/deploy.log" 2>&1;then ERROR_CLASS="source_deploy_failed";block source_deploy_failed;fi;DEPLOY="PASS"

PHASE="db_migrate"
cat > "$TMP/migrate.php" <<'PHP'
<?php
$db=[];require $argv[1];$s=json_decode(file_get_contents($argv[2]),true);$c=$db['default'];$p=$c['DBPrefix']??'dr_';if(!preg_match('/^[A-Za-z0-9_]+$/',$p))exit(50);$pdo=new PDO('mysql:host='.$c['hostname'].';dbname='.$c['database'].';charset=utf8mb4',$c['username'],$c['password'],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_EMULATE_PREPARES=>false]);$news=$p.'1_news';$cat=$p.'1_share_category';$share=$p.'1_share_index';$hits=$p.'1_news_hits';$main=$dataCount=$shareCount=$hitCount=0;$pdo->beginTransaction();
try{foreach([85,86] as $id){$st=$pdo->prepare("SELECT COUNT(*) FROM `$hits` WHERE id=? FOR UPDATE");$st->execute([$id]);if((int)$st->fetchColumn()!==0)throw new RuntimeException('hits drift');$st=$pdo->prepare("INSERT INTO `$hits` (`id`) VALUES (?)");$st->execute([$id]);if($st->rowCount()!==1)throw new RuntimeException('hits insert');$hitCount++;$st=$pdo->prepare("SELECT mid FROM `$share` WHERE id=? FOR UPDATE");$st->execute([$id]);if($st->fetchColumn()!==false)throw new RuntimeException('share drift');$st=$pdo->prepare("INSERT INTO `$share` (`id`,`mid`) VALUES (?,'news')");$st->execute([$id]);if($st->rowCount()!==1)throw new RuntimeException('share insert');$shareCount++;}
foreach($s['rows'] as $r){$id=(int)$r['id'];$tid=(int)$r['tableid'];$st=$pdo->prepare("UPDATE `$news` SET catid=3 WHERE id=? AND catid=7 AND status=9");$st->execute([$id]);if($st->rowCount()!==1)throw new RuntimeException('main drift');$main++;$dt=$p.'1_news_data_'.$tid;if(!preg_match('/^[A-Za-z0-9_]+$/',$dt))throw new RuntimeException('unsafe data');$st=$pdo->prepare("UPDATE `$dt` SET catid=3 WHERE id=? AND catid=7");$st->execute([$id]);if($st->rowCount()!==1)throw new RuntimeException('data drift');$dataCount++;}$st=$pdo->prepare("UPDATE `$cat` SET disabled=1,`show`=0 WHERE id=7 AND name='SEO文章' AND dirname='seo-articles' AND mid='news' AND disabled=0 AND `show`=1");$st->execute();if($st->rowCount()!==1)throw new RuntimeException('category drift');$pdo->commit();}catch(Throwable $e){if($pdo->inTransaction())$pdo->rollBack();fwrite(STDERR,$e->getMessage());exit(51);}echo json_encode(['main'=>$main,'data'=>$dataCount,'share'=>$shareCount,'hits'=>$hitCount]);
PHP
php "$TMP/migrate.php" "$WEBROOT/config/database.php" "$TMP/before.json" > "$TMP/migrate.json" || { ERROR_CLASS="db_migration_failed";block db_migration_failed; }
MMAIN=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["main"])' "$TMP/migrate.json");MDATA=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["data"])' "$TMP/migrate.json");MSHARE=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["share"])' "$TMP/migrate.json");MHITS=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["hits"])' "$TMP/migrate.json");[ "$MMAIN" -eq 4 ]&&[ "$MDATA" -eq 4 ]&&[ "$MSHARE" -eq 2 ]&&[ "$MHITS" -eq 2 ]||{ ERROR_CLASS="migration_count_wrong";block migration_count_wrong; };DB="PASS";SHARE="PASS";HITS="PASS";RETIRED="PASS"

PHASE="sitemap_regenerate";git show "$TARGET_SHA:scripts/seo/generate_sitemap.php" > "$TMP/sitemap.php";XYPTDQ_WEBROOT="$WEBROOT" XYPTDQ_DB_CONFIG="$WEBROOT/config/database.php" XYPTDQ_SITEMAP="$WEBROOT/sitemap.xml" php "$TMP/sitemap.php" >/dev/null || { ERROR_CLASS="sitemap_regeneration_failed";block sitemap_regeneration_failed; }

PHASE="db_verify"
php -r '$db=[];require $argv[1];$c=$db["default"];$p=$c["DBPrefix"]??"dr_";$pdo=new PDO("mysql:host=".$c["hostname"].";dbname=".$c["database"].";charset=utf8mb4",$c["username"],$c["password"],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);$n=$p."1_news";$cat=$p."1_share_category";$sh=$p."1_share_index";$h=$p."1_news_hits";$r=$pdo->query("SELECT disabled,`show` FROM `$cat` WHERE id=7")->fetch(PDO::FETCH_NUM);if(!$r||(int)$r[0]!==1||(int)$r[1]!==0)exit(1);if((int)$pdo->query("SELECT COUNT(*) FROM `$n` WHERE catid=7")->fetchColumn()!==0)exit(2);foreach([85,86,88,91] as $id){$st=$pdo->prepare("SELECT catid,status,tableid FROM `$n` WHERE id=?");$st->execute([$id]);$x=$st->fetch(PDO::FETCH_NUM);if(!$x||(int)$x[0]!==3||(int)$x[1]!==9)exit(3);$dt=$p."1_news_data_".(int)$x[2];$st=$pdo->prepare("SELECT catid FROM `$dt` WHERE id=?");$st->execute([$id]);if((int)$st->fetchColumn()!==3)exit(4);$st=$pdo->prepare("SELECT mid FROM `$sh` WHERE id=?");$st->execute([$id]);if($st->fetchColumn()!=="news")exit(5);$st=$pdo->prepare("SELECT COUNT(*) FROM `$h` WHERE id=?");$st->execute([$id]);if((int)$st->fetchColumn()!==1)exit(6);}' "$WEBROOT/config/database.php" || { ERROR_CLASS="db_post_verify_failed";block db_post_verify_failed; }

PHASE="redirect_verify"
redir(){ local u="$1" f="$2";curl -sk --max-time 30 -o /dev/null -D "$f" "$u" >/dev/null;local c l;c=$(awk 'toupper($1)~/^HTTP\//{x=$2}END{print x}' "$f");l=$(awk 'BEGIN{IGNORECASE=1}/^Location:/{sub(/\r$/,"");sub(/^[^:]*:[[:space:]]*/,"");print;exit}' "$f");[ "$c" = 301 ]&&[ "$l" = "$CANONICAL/index.php?c=category&dir=tzjq" ];}
if redir "$CANONICAL/index.php?c=category&dir=seo-articles" "$TMP/rd";then REDIR_DIR="PASS";else ERROR_CLASS="old_dir_redirect_failed";block old_dir_redirect_failed;fi;if redir "$CANONICAL/index.php?c=category&id=7" "$TMP/ri";then REDIR_ID="PASS";else ERROR_CLASS="old_id_redirect_failed";block old_id_redirect_failed;fi

PHASE="render_verify";c=$(curl -skL --max-time 30 -o "$TMP/tzjq" -w '%{http_code}' "$CANONICAL/index.php?c=category&dir=tzjq");[ "$c" = 200 ]||{ ERROR_CLASS="tzjq_not_200";block tzjq_not_200; };HTTP_OK=0;CAN_OK=0
for id in 85 86 88 91;do c=$(curl -skL --max-time 30 -o "$TMP/$id.after" -w '%{http_code}' "$CANONICAL/index.php?c=show&id=$id");[ "$c" = 200 ]||{ ERROR_CLASS="article_not_200";block article_not_200; };HTTP_OK=$((HTTP_OK+1));[ "$(canonical "$TMP/$id.after")" = "$CANONICAL/index.php?c=show&id=$id" ]||{ ERROR_CLASS="article_canonical_changed";block article_canonical_changed; };CAN_OK=$((CAN_OK+1));done
[ "$(description "$TMP/91.after")" = "$D91" ]||{ ERROR_CLASS="article91_description_changed";block article91_description_changed; };DESC91="PASS"
UA='Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 Chrome/134 Mobile Safari/537.36';curl -skL --max-time 30 -A "$UA" -o "$TMP/mob" "$CANONICAL/index.php?c=show&id=91"
python3 - "$TMP/91.after" "$TMP/mob" <<'PY' > "$TMP/nav.json"
import json,re,sys
def f(p,m):
 s=open(p,encoding='utf-8',errors='ignore').read();cls='category-nav' if m else 'xyptdq-site-nav';x=re.search(r'<nav\b[^>]*class=["\'][^"\']*\b'+re.escape(cls)+r'\b[^"\']*["\'][^>]*>(.*?)</nav\s*>',s,re.I|re.S)
 if not x:raise SystemExit(1)
 n=x.group(1);old=len(re.findall(r'href=["\'][^"\']*seo-articles[^"\']*["\']',n,re.I));tz=len(re.findall(r'href=["\'][^"\']*c=category(?:&amp;|&)dir=tzjq[^"\']*["\']',n,re.I));
 if tz<1:raise SystemExit(2)
 return old
print(json.dumps({'pc':f(sys.argv[1],False),'mobile':f(sys.argv[2],True)}))
PY
NAV_PC=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["pc"])' "$TMP/nav.json");NAV_MOBILE=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["mobile"])' "$TMP/nav.json");[ "$NAV_PC" -eq 0 ]&&[ "$NAV_MOBILE" -eq 0 ]||{ ERROR_CLASS="old_nav_present";block old_nav_present; }
for id in 74 75;do curl -skL --max-time 30 -o "$TMP/h$id" "$CANONICAL/index.php?c=show&id=$id";done;[ "$(h1 "$TMP/h74")" = '长征（送首冲）｜软件项目' ]&&[ "$(h1 "$TMP/h75")" = '长征（送首冲）｜福利资源' ]||{ ERROR_CLASS="h1_control_regressed";block h1_control_regressed; };H1CTRL="PASS"

PHASE="sitemap_verify"
python3 - "$WEBROOT/sitemap.xml" <<'PY' > "$TMP/sm.json"
import json,sys,xml.etree.ElementTree as E
u=[e.text.strip() for e in E.parse(sys.argv[1]).getroot().iter() if e.tag.endswith('loc') and e.text];b='https://www.laocaimi.org';print(json.dumps({'old':u.count(b+'/index.php?c=category&dir=seo-articles'),'tz':u.count(b+'/index.php?c=category&dir=tzjq'),'arts':sum(b+f'/index.php?c=show&id={i}' in u for i in [85,86,88,91])}))
PY
OLD_SITEMAP=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["old"])' "$TMP/sm.json");TZ_SITEMAP=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["tz"])' "$TMP/sm.json");ARTICLE_SITEMAP=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["arts"])' "$TMP/sm.json");[ "$OLD_SITEMAP" -eq 0 ]&&[ "$TZ_SITEMAP" -eq 1 ]&&[ "$ARTICLE_SITEMAP" -eq 4 ]||{ ERROR_CLASS="sitemap_verify_failed";block sitemap_verify_failed; }
PHASE="framework_verify";if [ -f "$WEBROOT/dayrui/CodeIgniter72/System/Cache/CacheFactory.php" ]&&[ -f "$WEBROOT/cache/frame.lock" ]&&[ "$(od -An -tx1 -v "$WEBROOT/cache/frame.lock"|tr -d ' \n')" = "$EXPECTED_FRAME_LOCK_HEX" ];then FRAMEWORK="PASS";else ERROR_CLASS="framework_integrity_failed";block framework_integrity_failed;fi
PHASE="final";trap - ERR;ERROR_CLASS="NONE";BLOCKER="NONE";emit PASS;echo 'CONSOLIDATE_SEO_ARTICLES_INTO_TZJQ_V3=PASS'
