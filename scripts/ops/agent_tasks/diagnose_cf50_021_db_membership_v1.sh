#!/bin/bash
# Read-only diagnostic for why CMS 94 is omitted by generate_sitemap.php.
set -euo pipefail
umask 077
RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
[ -n "$RESULT_FILE" ] || exit 2
TMP=$(mktemp -d /tmp/xyptdq-021-dbdiag.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

php - "$WEBROOT/config/database.php" "$TMP/db.json" <<'PHP'
<?php
declare(strict_types=1);
$configPath=$argv[1]; $out=$argv[2];
$db=[]; require $configPath;
$c=$db['default']??null;
if(!is_array($c)){fwrite(STDERR,"bad db config\n"); exit(3);}
$prefix=(string)($c['DBPrefix']??'dr_');
if(!preg_match('/^[A-Za-z0-9_]+$/',$prefix)){exit(4);}
$pdo=new PDO('mysql:host='.(string)$c['hostname'].';dbname='.(string)$c['database'].';charset=utf8mb4',(string)$c['username'],(string)$c['password'],[
 PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC,PDO::ATTR_EMULATE_PREPARES=>false]);
$dbname=(string)$c['database'];
function tex(PDO $pdo,string $db,string $t): bool { $s=$pdo->prepare('SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=:d AND table_name=:t'); $s->execute([':d'=>$db,':t'=>$t]); return (int)$s->fetchColumn()>0; }
function one(PDO $pdo,string $sql,array $p=[]): array { $s=$pdo->prepare($sql); $s->execute($p); $r=$s->fetch(); return is_array($r)?$r:[]; }
$news=$prefix.'1_news'; $share=$prefix.'1_share_index'; $registry=$prefix.'xyptdq_publish_registry';
$r=['db_prefix'=>$prefix,'tables'=>['news'=>tex($pdo,$dbname,$news),'share_index'=>tex($pdo,$dbname,$share),'registry'=>tex($pdo,$dbname,$registry)]];
if($r['tables']['news']) $r['news_94']=one($pdo,'SELECT `id`,`catid`,`title`,`status`,`url`,`tableid`,`updatetime` FROM `'.$news.'` WHERE `id`=94 LIMIT 1'); else $r['news_94']=[];
if($r['tables']['share_index']) $r['share_94']=one($pdo,'SELECT `id`,`mid` FROM `'.$share.'` WHERE `id`=94 LIMIT 1'); else $r['share_94']=[];
if($r['tables']['registry']) $r['registry_94']=one($pdo,'SELECT `article_key`,`cms_id`,`content_hash`,`source_file`,`published_at` FROM `'.$registry.'` WHERE `cms_id`=94 LIMIT 1'); else $r['registry_94']=[];
$r['generator_join_94']=[];
if($r['tables']['news'] && $r['tables']['share_index']) {
 $r['generator_join_94']=one($pdo,'SELECT m.`id`,m.`url`,m.`status`,m.`updatetime`,s.`mid` FROM `'.$news.'` m INNER JOIN `'.$share.'` s ON s.`id`=m.`id` AND s.`mid`=:mid WHERE m.`status`=9 AND m.`id`=94 LIMIT 1',[':mid'=>'news']);
}
file_put_contents($out,json_encode($r,JSON_PRETTY_PRINT|JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES)."\n");
PHP

GEN_RC=99
set +e
XYPTDQ_WEBROOT="$WEBROOT" XYPTDQ_DB_CONFIG="$WEBROOT/config/database.php" XYPTDQ_SITEMAP="$TMP/generated.xml" php "$REPO/scripts/seo/generate_sitemap.php" >"$TMP/gen.out" 2>"$TMP/gen.err"
GEN_RC=$?
set -e

python3 - "$RESULT_FILE" "$TMP/db.json" "$TMP/generated.xml" "$TMP/gen.out" "$TMP/gen.err" "$GEN_RC" <<'PY'
import html,json,pathlib,re,sys
out,dbp,xmlp,stdoutp,stderrp,rc=sys.argv[1:]
db=json.loads(pathlib.Path(dbp).read_text(encoding='utf-8'))
xml=pathlib.Path(xmlp).read_text(encoding='utf-8',errors='ignore') if pathlib.Path(xmlp).exists() else ''
locs=[html.unescape(x.strip()) for x in re.findall(r'<loc>(.*?)</loc>',xml,re.I|re.S)]
relevant=[u for u in locs if 'id=94' in u or 'ffc-five-direct-distinct4' in u]
p={
 'task':'diagnose_cf50_021_db_membership_v1','status':'PASS','read_only':True,'cms_id':94,
 'database_membership':db,'generator_exit_code':int(rc),'generator_url_count':len(locs),
 'generator_relevant_locs':relevant,
 'generator_stdout':pathlib.Path(stdoutp).read_text(encoding='utf-8',errors='ignore')[-2000:],
 'generator_stderr':pathlib.Path(stderrp).read_text(encoding='utf-8',errors='ignore')[-2000:],
 'cms_write_attempted':False,'production_sitemap_mutated':False,'cron_mutated':False,'queue_consumed':False
}
news=db.get('news_94') or {}; share=db.get('share_94') or {}; reg=db.get('registry_94') or {}; join=db.get('generator_join_94') or {}
if not news: cause='cms_news_row_missing'
elif int(news.get('status') or 0)!=9: cause='cms_news_status_not_published'
elif not share: cause='share_index_row_missing'
elif str(share.get('mid') or '')!='news': cause='share_index_mid_mismatch'
elif not join: cause='generator_inner_join_excludes_94'
elif not reg: cause='publisher_registry_row_missing'
elif not relevant: cause='row_eligible_but_generator_url_construction_or_registry_table_resolution_wrong'
else: cause='no_omission_in_current_generator'
p['root_cause_candidate']=cause
with open(out,'w',encoding='utf-8') as f: json.dump(p,f,ensure_ascii=False,indent=2,sort_keys=True); f.write('\n')
PY

echo CF50_021_DB_MEMBERSHIP_DIAG=PASS
