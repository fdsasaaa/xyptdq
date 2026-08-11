#!/bin/bash
# Rollback-gated consolidation of the legacy SEO文章 category into tzjq/catid=3.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
CANONICAL="https://www.laocaimi.org"
TARGET_SHA="00d691001c6b5cd369ec89afeabc39b87bc12f51"
EXPECTED_FRAME_LOCK_HEX="436f646549676e697465723732"
PHASE="init"
DEPLOY="NO"
DB_MIGRATION="NO"
ROLLBACK="NO"
MIGRATED_MAIN=0
MIGRATED_DATA=0
CATEGORY_RETIRED="NO"
ARTICLE_HTTP_OK=0
ARTICLE_CANONICAL_OK=0
PC_OLD_NAV_LINKS=-1
MOBILE_OLD_NAV_LINKS=-1
SITEMAP_OLD_CATEGORY_COUNT=-1
SITEMAP_TZJQ_COUNT=-1
OLD_DIR_REDIRECT="NO"
OLD_ID_REDIRECT="NO"
ARTICLE91_DESCRIPTION_UNCHANGED="NO"
H1_CONTROLS_OK="NO"
FRAMEWORK_OK="NO"
ERROR_CLASS="NONE"
BLOCKING_ITEM="NONE"

[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3
[ -d "$WEBROOT" ] || exit 4
[ -f "$WEBROOT/config/database.php" ] || exit 5

TMP="$(mktemp -d /tmp/xyptdq-seo-articles-consolidate.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

write_payload(){
  local status="$1"
  python3 - "$RESULT_FILE" "$status" "$PHASE" "$TARGET_SHA" "$DEPLOY" "$DB_MIGRATION" "$ROLLBACK" \
    "$MIGRATED_MAIN" "$MIGRATED_DATA" "$CATEGORY_RETIRED" "$ARTICLE_HTTP_OK" "$ARTICLE_CANONICAL_OK" \
    "$PC_OLD_NAV_LINKS" "$MOBILE_OLD_NAV_LINKS" "$SITEMAP_OLD_CATEGORY_COUNT" "$SITEMAP_TZJQ_COUNT" \
    "$OLD_DIR_REDIRECT" "$OLD_ID_REDIRECT" "$ARTICLE91_DESCRIPTION_UNCHANGED" "$H1_CONTROLS_OK" \
    "$FRAMEWORK_OK" "$ERROR_CLASS" "$BLOCKING_ITEM" <<'PY'
import json,sys
(out,status,phase,target,deploy,dbmig,rollback,mainc,datac,retired,httpok,canok,pcold,mold,sold,stzjq,rdir,rid,desc,h1,framework,error,blocker)=sys.argv[1:]
p={
  "task":"consolidate_seo_articles_into_tzjq_v1",
  "deployment_status":status,
  "phase":phase,
  "target_sha":target,
  "deploy":deploy,
  "db_migration":dbmig,
  "rollback":rollback,
  "migrated_main_rows":int(mainc),
  "migrated_data_rows":int(datac),
  "legacy_category_retired":retired,
  "article_http_200_count":int(httpok),
  "article_canonical_unchanged_count":int(canok),
  "pc_old_nav_link_count":int(pcold),
  "mobile_old_nav_link_count":int(mold),
  "sitemap_old_category_count":int(sold),
  "sitemap_tzjq_count":int(stzjq),
  "old_dir_route_301_to_tzjq":rdir,
  "old_id_route_301_to_tzjq":rid,
  "article91_description_unchanged":desc,
  "h1_controls_74_75":h1,
  "framework_integrity":framework,
  "deploy_error_class":error,
  "blocking_item":blocker,
  "article_publishing_attempted":False,
  "publisher_cron_changed":False,
  "scheduled_queue_consumed":False,
  "secrets_disclosed":False
}
with open(out,'w',encoding='utf-8') as f:
    json.dump(p,f,ensure_ascii=False,indent=2,sort_keys=True); f.write('\n')
PY
}

extract_canonical(){
  python3 - "$1" <<'PY'
import html,re,sys
s=open(sys.argv[1],encoding='utf-8',errors='ignore').read()
for tag in re.findall(r'<link\b[^>]*>',s,re.I|re.S):
    rel=re.search(r'\brel\s*=\s*["\']([^"\']*)["\']',tag,re.I|re.S)
    if not rel or 'canonical' not in html.unescape(rel.group(1)).lower().split():
        continue
    h=re.search(r'\bhref\s*=\s*["\']([^"\']*)["\']',tag,re.I|re.S)
    print(html.unescape(h.group(1)).strip() if h else '')
    break
PY
}

extract_desc(){
  python3 - "$1" <<'PY'
import html,re,sys
s=open(sys.argv[1],encoding='utf-8',errors='ignore').read()
for tag in re.findall(r'<meta\b[^>]*>',s,re.I|re.S):
    n=re.search(r'\bname\s*=\s*["\']([^"\']*)["\']',tag,re.I|re.S)
    if not n or html.unescape(n.group(1)).strip().lower()!='description':
        continue
    c=re.search(r'\bcontent\s*=\s*["\']([^"\']*)["\']',tag,re.I|re.S)
    print(html.unescape(c.group(1)).strip() if c else '')
    break
PY
}

extract_h1(){
  python3 - "$1" <<'PY'
import html,re,sys
s=open(sys.argv[1],encoding='utf-8',errors='ignore').read()
m=re.search(r'<h1\b[^>]*>(.*?)</h1\s*>',s,re.I|re.S)
if m:
    print(' '.join(html.unescape(re.sub(r'<[^>]+>',' ',m.group(1))).split()))
PY
}

restore_all(){
  set +e
  if [ "$DB_MIGRATION" = "PASS" ] && [ -s "$TMP/before.json" ]; then
    cat > "$TMP/restore.php" <<'PHP'
<?php
$db=[]; require $argv[1];
$snap=json_decode(file_get_contents($argv[2]),true);
$c=$db['default'];
$prefix=$c['DBPrefix'] ?? 'dr_';
if (!preg_match('/^[A-Za-z0-9_]+$/',$prefix)) exit(20);
$pdo=new PDO('mysql:host='.$c['hostname'].';dbname='.$c['database'].';charset=utf8mb4',$c['username'],$c['password'],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);
$news=$prefix.'1_news'; $cat=$prefix.'1_share_category';
$pdo->beginTransaction();
try {
  foreach ($snap['rows'] as $r) {
    $id=(int)$r['id']; $old=(int)$r['catid']; $tableid=(int)$r['tableid']; $oldData=(int)$r['data_catid'];
    $st=$pdo->prepare("UPDATE `$news` SET catid=? WHERE id=?"); $st->execute([$old,$id]);
    $data=$prefix.'1_news_data_'.$tableid;
    if (!preg_match('/^[A-Za-z0-9_]+$/',$data)) throw new RuntimeException('unsafe data table');
    $st=$pdo->prepare("UPDATE `$data` SET catid=? WHERE id=?"); $st->execute([$oldData,$id]);
  }
  $cat7=$snap['category7'];
  $st=$pdo->prepare("UPDATE `$cat` SET disabled=?,`show`=? WHERE id=7 AND dirname='seo-articles'");
  $st->execute([(int)$cat7['disabled'],(int)$cat7['show_flag']]);
  $pdo->commit();
} catch(Throwable $e) { if($pdo->inTransaction()) $pdo->rollBack(); exit(21); }
PHP
    php "$TMP/restore.php" "$WEBROOT/config/database.php" "$TMP/before.json" >/dev/null 2>&1 && ROLLBACK="YES"
  fi
  if [ -d "$TMP/template.before" ]; then
    rm -rf "$WEBROOT/template"
    cp -a "$TMP/template.before" "$WEBROOT/template"
    ROLLBACK="YES"
  fi
  if [ -f "$TMP/index.before" ]; then
    cp -a "$TMP/index.before" "$WEBROOT/index.php"
    ROLLBACK="YES"
  fi
  if [ -f "$TMP/sitemap.before" ]; then
    cp -a "$TMP/sitemap.before" "$WEBROOT/sitemap.xml"
  fi
  chown -R www-data:www-data "$WEBROOT/template" "$WEBROOT/index.php" "$WEBROOT/sitemap.xml" 2>/dev/null || true
  set -e
}

block(){
  BLOCKING_ITEM="$1"
  if [ "$DEPLOY" = "PASS" ] || [ "$DB_MIGRATION" = "PASS" ]; then restore_all; fi
  write_payload BLOCKED
  echo "[seo-articles-consolidate] BLOCKED: $BLOCKING_ITEM class=$ERROR_CLASS" >&2
  exit 1
}

on_err(){
  rc=$?
  trap - ERR
  ERROR_CLASS="unhandled_runtime_error"
  BLOCKING_ITEM="phase_${PHASE}_exit_${rc}"
  if [ "$DEPLOY" = "PASS" ] || [ "$DB_MIGRATION" = "PASS" ]; then restore_all; fi
  write_payload BLOCKED || true
  exit "$rc"
}
trap on_err ERR

PHASE="repo_sync"
cd "$REPO"
git fetch --prune origin >/dev/null 2>&1
git merge-base --is-ancestor "$TARGET_SHA" origin/main || { ERROR_CLASS="target_not_in_main"; block target_not_in_main; }

PHASE="source_verify"
python3 - "$REPO" "$TARGET_SHA" <<'PY'
import json,subprocess,sys
repo,sha=sys.argv[1:]
def show(path):
    return subprocess.check_output(['git','-C',repo,'show',f'{sha}:{path}'],text=True)
cat=json.loads(show('config/content_category_map.json'))
if 'seo-articles' in cat.get('categories',{}): raise SystemExit(10)
if cat.get('policy',{}).get('seo_article_category_key')!='tzjq': raise SystemExit(11)
if 'seo-articles' not in cat.get('policy',{}).get('retired_category_keys',[]): raise SystemExit(12)
for p in ['site/template/pc/default/home/seo_header.html','site/template/mobile/default/home/seo_header.html']:
    s=show(p)
    if '/index.php?c=category&dir=seo-articles' in s: raise SystemExit(13)
    for d in ['gjfa','tzjq','zyyy']:
        if f'/index.php?c=category&dir={d}' not in s: raise SystemExit(14)
idx=show('site/index.php')
if "seo-articles" not in idx or "header('Location: https://www.laocaimi.org/index.php?c=category&dir=tzjq', true, 301)" not in idx:
    raise SystemExit(15)
policy=json.loads(show('config/content_publication_policy.json'))
if policy.get('publishing_enabled') is not False: raise SystemExit(16)
PY

PHASE="db_precondition"
cat > "$TMP/snapshot.php" <<'PHP'
<?php
$db=[]; require $argv[1];
$c=$db['default']; $prefix=$c['DBPrefix'] ?? 'dr_';
if (!preg_match('/^[A-Za-z0-9_]+$/',$prefix)) exit(30);
$pdo=new PDO('mysql:host='.$c['hostname'].';dbname='.$c['database'].';charset=utf8mb4',$c['username'],$c['password'],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC]);
$cat=$prefix.'1_share_category'; $news=$prefix.'1_news'; $share=$prefix.'1_share_index';
$cat3=$pdo->query("SELECT id,name,dirname,mid,disabled,`show` AS show_flag FROM `$cat` WHERE id=3 LIMIT 1")->fetch();
$cat7=$pdo->query("SELECT id,name,dirname,mid,disabled,`show` AS show_flag FROM `$cat` WHERE id=7 LIMIT 1")->fetch();
if(!$cat3||$cat3['name']!=='投注机巧'||$cat3['dirname']!=='tzjq'||$cat3['mid']!=='news'||(int)$cat3['disabled']!==0||(int)$cat3['show_flag']!==1) exit(31);
if(!$cat7||$cat7['name']!=='SEO文章'||$cat7['dirname']!=='seo-articles'||$cat7['mid']!=='news'||(int)$cat7['disabled']!==0||(int)$cat7['show_flag']!==1) exit(32);
$expected=[85=>'2026年最新信誉平台排行榜与评测',86=>'平台安全防护措施详解：从注册到使用',88=>'分分彩投注技巧：先看命中率、奖金与资金风险',91=>'分分彩投注技巧：先算命中率、单期成本还是返奖？'];
$rows=$pdo->query("SELECT id,catid,status,title,tableid FROM `$news` WHERE id IN (85,86,88,91) ORDER BY id")->fetchAll();
if(count($rows)!==4) exit(33);
if((int)$pdo->query("SELECT COUNT(*) FROM `$news` WHERE catid=7")->fetchColumn()!==4) exit(34);
foreach($rows as &$r){
  $id=(int)$r['id'];
  if(!isset($expected[$id])||$r['title']!==$expected[$id]||(int)$r['catid']!==7||(int)$r['status']!==9) exit(35);
  $tid=(int)$r['tableid']; if($tid<0||$tid>9999) exit(36);
  $data=$prefix.'1_news_data_'.$tid; if(!preg_match('/^[A-Za-z0-9_]+$/',$data)) exit(37);
  $st=$pdo->prepare("SELECT id,catid FROM `$data` WHERE id=? LIMIT 1"); $st->execute([$id]); $dr=$st->fetch();
  if(!$dr||(int)$dr['catid']!==7) exit(38);
  $r['data_catid']=(int)$dr['catid'];
  $st=$pdo->prepare("SELECT id,mid FROM `$share` WHERE id=? LIMIT 1"); $st->execute([$id]); $sr=$st->fetch();
  if(!$sr||$sr['mid']!=='news') exit(39);
}
unset($r);
echo json_encode(['category3'=>$cat3,'category7'=>$cat7,'rows'=>$rows],JSON_UNESCAPED_UNICODE|JSON_PRETTY_PRINT|JSON_UNESCAPED_SLASHES);
PHP
php "$TMP/snapshot.php" "$WEBROOT/config/database.php" > "$TMP/before.json" || { ERROR_CLASS="db_precondition_mismatch"; block db_precondition_mismatch; }

PHASE="http_precondition"
for id in 85 86 88 91; do
  code=$(curl -sk --max-time 30 -o "$TMP/article-$id.before.html" -w '%{http_code}' "$CANONICAL/index.php?c=show&id=$id")
  [ "$code" = 200 ] || { ERROR_CLASS="baseline_article_http_not_200"; block baseline_article_http_not_200; }
  can="$(extract_canonical "$TMP/article-$id.before.html")"
  [ "$can" = "$CANONICAL/index.php?c=show&id=$id" ] || { ERROR_CLASS="baseline_article_canonical_unexpected"; block baseline_article_canonical_unexpected; }
done
ARTICLE91_DESC_BEFORE="$(extract_desc "$TMP/article-91.before.html")"
[ -n "$ARTICLE91_DESC_BEFORE" ] || { ERROR_CLASS="article91_baseline_description_missing"; block article91_baseline_description_missing; }

PHASE="rollback_snapshot"
cp -a "$WEBROOT/template" "$TMP/template.before"
cp -a "$WEBROOT/index.php" "$TMP/index.before"
cp -a "$WEBROOT/sitemap.xml" "$TMP/sitemap.before"

PHASE="deploy_source"
git show "$TARGET_SHA:scripts/deploy_safe.sh" > "$TMP/deploy_safe.sh" || { ERROR_CLASS="deploy_safe_missing"; block deploy_safe_missing; }
chmod 700 "$TMP/deploy_safe.sh"
if ! XYPTDQ_REPO_DIR="$REPO" XYPTDQ_WEBROOT="$WEBROOT" bash "$TMP/deploy_safe.sh" "$TARGET_SHA" > "$TMP/deploy.log" 2>&1; then
  ERROR_CLASS="source_deploy_failed"; block source_deploy_failed
fi
DEPLOY="PASS"

PHASE="db_migrate"
cat > "$TMP/migrate.php" <<'PHP'
<?php
$db=[]; require $argv[1]; $snap=json_decode(file_get_contents($argv[2]),true);
$c=$db['default']; $prefix=$c['DBPrefix'] ?? 'dr_';
if(!preg_match('/^[A-Za-z0-9_]+$/',$prefix)) exit(40);
$pdo=new PDO('mysql:host='.$c['hostname'].';dbname='.$c['database'].';charset=utf8mb4',$c['username'],$c['password'],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);
$news=$prefix.'1_news'; $cat=$prefix.'1_share_category'; $main=0; $dataCount=0;
$pdo->beginTransaction();
try {
  foreach($snap['rows'] as $r){
    $id=(int)$r['id']; $tid=(int)$r['tableid'];
    $st=$pdo->prepare("UPDATE `$news` SET catid=3 WHERE id=? AND catid=7 AND status=9"); $st->execute([$id]); if($st->rowCount()!==1) throw new RuntimeException('main row drift'); $main++;
    $data=$prefix.'1_news_data_'.$tid; if(!preg_match('/^[A-Za-z0-9_]+$/',$data)) throw new RuntimeException('unsafe data table');
    $st=$pdo->prepare("UPDATE `$data` SET catid=3 WHERE id=? AND catid=7"); $st->execute([$id]); if($st->rowCount()!==1) throw new RuntimeException('data row drift'); $dataCount++;
  }
  $st=$pdo->prepare("UPDATE `$cat` SET disabled=1,`show`=0 WHERE id=7 AND name='SEO文章' AND dirname='seo-articles' AND mid='news' AND disabled=0 AND `show`=1");
  $st->execute(); if($st->rowCount()!==1) throw new RuntimeException('category row drift');
  $pdo->commit();
} catch(Throwable $e){ if($pdo->inTransaction()) $pdo->rollBack(); fwrite(STDERR,$e->getMessage()); exit(41); }
echo json_encode(['main'=>$main,'data'=>$dataCount]);
PHP
php "$TMP/migrate.php" "$WEBROOT/config/database.php" "$TMP/before.json" > "$TMP/migrate.json" || { ERROR_CLASS="db_migration_failed"; block db_migration_failed; }
MIGRATED_MAIN=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["main"])' "$TMP/migrate.json")
MIGRATED_DATA=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["data"])' "$TMP/migrate.json")
[ "$MIGRATED_MAIN" -eq 4 ] || { ERROR_CLASS="main_migration_count_wrong"; block main_migration_count_wrong; }
[ "$MIGRATED_DATA" -eq 4 ] || { ERROR_CLASS="data_migration_count_wrong"; block data_migration_count_wrong; }
DB_MIGRATION="PASS"
CATEGORY_RETIRED="PASS"

PHASE="regenerate_sitemap"
git show "$TARGET_SHA:scripts/seo/generate_sitemap.php" > "$TMP/generate_sitemap.php" || { ERROR_CLASS="sitemap_generator_missing"; block sitemap_generator_missing; }
XYPTDQ_WEBROOT="$WEBROOT" XYPTDQ_DB_CONFIG="$WEBROOT/config/database.php" XYPTDQ_SITEMAP="$WEBROOT/sitemap.xml" php "$TMP/generate_sitemap.php" > "$TMP/sitemap.log" 2>&1 || { ERROR_CLASS="sitemap_regeneration_failed"; block sitemap_regeneration_failed; }

PHASE="db_verify"
cat > "$TMP/verify.php" <<'PHP'
<?php
$db=[];require $argv[1];$c=$db['default'];$prefix=$c['DBPrefix']??'dr_';if(!preg_match('/^[A-Za-z0-9_]+$/',$prefix))exit(50);
$pdo=new PDO('mysql:host='.$c['hostname'].';dbname='.$c['database'].';charset=utf8mb4',$c['username'],$c['password'],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC]);
$news=$prefix.'1_news';$cat=$prefix.'1_share_category';
$r=$pdo->query("SELECT disabled,`show` AS show_flag FROM `$cat` WHERE id=7 AND dirname='seo-articles' LIMIT 1")->fetch();
if(!$r||(int)$r['disabled']!==1||(int)$r['show_flag']!==0)exit(51);
if((int)$pdo->query("SELECT COUNT(*) FROM `$news` WHERE catid=7")->fetchColumn()!==0)exit(52);
$rows=$pdo->query("SELECT id,catid,status,tableid FROM `$news` WHERE id IN (85,86,88,91) ORDER BY id")->fetchAll();if(count($rows)!==4)exit(53);
foreach($rows as $x){if((int)$x['catid']!==3||(int)$x['status']!==9)exit(54);$data=$prefix.'1_news_data_'.(int)$x['tableid'];$st=$pdo->prepare("SELECT catid FROM `$data` WHERE id=? LIMIT 1");$st->execute([(int)$x['id']]);if((int)$st->fetchColumn()!==3)exit(55);} echo 'PASS';
PHP
php "$TMP/verify.php" "$WEBROOT/config/database.php" >/dev/null || { ERROR_CLASS="db_post_verify_failed"; block db_post_verify_failed; }

PHASE="redirect_verify"
check_redirect(){
  local url="$1"
  local out="$2"
  curl -sk --max-time 30 -o /dev/null -D "$out" "$url" >/dev/null
  local code
  code=$(awk 'toupper($1) ~ /^HTTP\// {c=$2} END{print c}' "$out")
  local loc
  loc=$(awk 'BEGIN{IGNORECASE=1} /^Location:/ {sub(/\r$/,""); sub(/^[^:]*:[[:space:]]*/,""); print; exit}' "$out")
  [ "$code" = 301 ] && [ "$loc" = "$CANONICAL/index.php?c=category&dir=tzjq" ]
}
if check_redirect "$CANONICAL/index.php?c=category&dir=seo-articles" "$TMP/redirect-dir.headers"; then OLD_DIR_REDIRECT="PASS"; else ERROR_CLASS="old_dir_redirect_failed"; block old_dir_redirect_failed; fi
if check_redirect "$CANONICAL/index.php?c=category&id=7" "$TMP/redirect-id.headers"; then OLD_ID_REDIRECT="PASS"; else ERROR_CLASS="old_id_redirect_failed"; block old_id_redirect_failed; fi

PHASE="render_verify"
TZJQ_CODE=$(curl -skL --max-time 30 -o "$TMP/tzjq.html" -w '%{http_code}' "$CANONICAL/index.php?c=category&dir=tzjq")
[ "$TZJQ_CODE" = 200 ] || { ERROR_CLASS="tzjq_http_not_200"; block tzjq_http_not_200; }
ARTICLE_HTTP_OK=0; ARTICLE_CANONICAL_OK=0
for id in 85 86 88 91; do
  code=$(curl -skL --max-time 30 -o "$TMP/article-$id.after.html" -w '%{http_code}' "$CANONICAL/index.php?c=show&id=$id")
  [ "$code" = 200 ] || { ERROR_CLASS="article_http_not_200"; block article_http_not_200; }
  ARTICLE_HTTP_OK=$((ARTICLE_HTTP_OK+1))
  can="$(extract_canonical "$TMP/article-$id.after.html")"
  [ "$can" = "$CANONICAL/index.php?c=show&id=$id" ] || { ERROR_CLASS="article_canonical_changed"; block article_canonical_changed; }
  ARTICLE_CANONICAL_OK=$((ARTICLE_CANONICAL_OK+1))
done
ARTICLE91_DESC_AFTER="$(extract_desc "$TMP/article-91.after.html")"
[ "$ARTICLE91_DESC_AFTER" = "$ARTICLE91_DESC_BEFORE" ] || { ERROR_CLASS="article91_description_changed"; block article91_description_changed; }
ARTICLE91_DESCRIPTION_UNCHANGED="PASS"

MOBILE_UA='Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 Chrome/134 Mobile Safari/537.36'
curl -skL --max-time 30 -A "$MOBILE_UA" -o "$TMP/article-91.mobile.html" "$CANONICAL/index.php?c=show&id=91"
python3 - "$TMP/article-91.after.html" "$TMP/article-91.mobile.html" <<'PY' > "$TMP/nav.json"
import html,json,re,sys

def count(path,mobile):
 s=open(path,encoding='utf-8',errors='ignore').read()
 cls='category-nav' if mobile else 'xyptdq-site-nav'
 m=re.search(r'<nav\b[^>]*class=["\'][^"\']*\b'+re.escape(cls)+r'\b[^"\']*["\'][^>]*>(.*?)</nav\s*>',s,re.I|re.S)
 if not m: raise SystemExit(1)
 nav=m.group(1)
 old=len(re.findall(r'href=["\'][^"\']*seo-articles[^"\']*["\']',nav,re.I))
 tz=len(re.findall(r'href=["\'][^"\']*c=category(?:&amp;|&)dir=tzjq[^"\']*["\']',nav,re.I))
 if tz<1: raise SystemExit(2)
 return old
print(json.dumps({'pc':count(sys.argv[1],False),'mobile':count(sys.argv[2],True)}))
PY
PC_OLD_NAV_LINKS=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["pc"])' "$TMP/nav.json")
MOBILE_OLD_NAV_LINKS=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["mobile"])' "$TMP/nav.json")
[ "$PC_OLD_NAV_LINKS" -eq 0 ] || { ERROR_CLASS="pc_old_nav_link_present"; block pc_old_nav_link_present; }
[ "$MOBILE_OLD_NAV_LINKS" -eq 0 ] || { ERROR_CLASS="mobile_old_nav_link_present"; block mobile_old_nav_link_present; }

for id in 74 75; do curl -skL --max-time 30 -o "$TMP/h1-$id.html" "$CANONICAL/index.php?c=show&id=$id"; done
[ "$(extract_h1 "$TMP/h1-74.html")" = '长征（送首冲）｜软件项目' ] || { ERROR_CLASS="h1_74_regressed"; block h1_74_regressed; }
[ "$(extract_h1 "$TMP/h1-75.html")" = '长征（送首冲）｜福利资源' ] || { ERROR_CLASS="h1_75_regressed"; block h1_75_regressed; }
H1_CONTROLS_OK="PASS"

PHASE="sitemap_verify"
python3 - "$WEBROOT/sitemap.xml" <<'PY' > "$TMP/sitemap.json"
import json,sys,xml.etree.ElementTree as ET
root=ET.parse(sys.argv[1]).getroot()
locs=[]
for e in root.iter():
    if e.tag.endswith('loc') and e.text: locs.append(e.text.strip())
old='https://www.laocaimi.org/index.php?c=category&dir=seo-articles'
tz='https://www.laocaimi.org/index.php?c=category&dir=tzjq'
for i in [85,86,88,91]:
    if f'https://www.laocaimi.org/index.php?c=show&id={i}' not in locs: raise SystemExit(60)
print(json.dumps({'old':locs.count(old),'tzjq':locs.count(tz)}))
PY
SITEMAP_OLD_CATEGORY_COUNT=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["old"])' "$TMP/sitemap.json")
SITEMAP_TZJQ_COUNT=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["tzjq"])' "$TMP/sitemap.json")
[ "$SITEMAP_OLD_CATEGORY_COUNT" -eq 0 ] || { ERROR_CLASS="old_category_still_in_sitemap"; block old_category_still_in_sitemap; }
[ "$SITEMAP_TZJQ_COUNT" -eq 1 ] || { ERROR_CLASS="tzjq_sitemap_count_wrong"; block tzjq_sitemap_count_wrong; }

PHASE="framework_verify"
if [ -f "$WEBROOT/dayrui/CodeIgniter72/System/Cache/CacheFactory.php" ] \
   && [ -f "$WEBROOT/cache/frame.lock" ] \
   && [ "$(od -An -tx1 -v "$WEBROOT/cache/frame.lock" | tr -d ' \n')" = "$EXPECTED_FRAME_LOCK_HEX" ]; then
  FRAMEWORK_OK="PASS"
else
  ERROR_CLASS="framework_integrity_failed"; block framework_integrity_failed
fi

PHASE="final"
trap - ERR
ERROR_CLASS="NONE"
BLOCKING_ITEM="NONE"
write_payload PASS
echo "CONSOLIDATE_SEO_ARTICLES_INTO_TZJQ_V1=PASS migrated=4 old_sitemap=0"
