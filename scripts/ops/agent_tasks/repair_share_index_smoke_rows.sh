#!/bin/bash
# Repair only the two reviewed direct-SQL smoke articles (88/89) that are
# complete in the news module but missing Xunrui's shared routing index.
# Fail closed on cross-module ID collisions; take and verify a full backup first.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
CANONICAL="https://www.laocaimi.org"
IDS=(88 89)
PHASE="init"
BACKUP_VERIFY="NO"
REPAIR="NO"
SITEMAP="NO"
AI_AFTER=0
BEFORE_88=0
BEFORE_89=0
AFTER_88=0
AFTER_89=0

[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3
[ -d "$WEBROOT" ] || exit 4

write_payload() {
  local status="$1"
  local blocker="$2"
  python3 - "$RESULT_FILE" "$status" "$blocker" "$PHASE" "$BACKUP_VERIFY" "$REPAIR" "$SITEMAP" "$AI_AFTER" "$BEFORE_88" "$BEFORE_89" "$AFTER_88" "$AFTER_89" <<'PY'
import json,sys
(out,status,blocker,phase,backup,repair,sitemap,ai,b88,b89,a88,a89)=sys.argv[1:]
payload={
  'task':'repair_share_index_smoke_rows',
  'repair_status':status,
  'phase':phase,
  'blocking_item':blocker,
  'backup_verification':backup,
  'share_index_repair':repair,
  'sitemap_regenerated':sitemap,
  'share_index_auto_increment_after':int(ai),
  'http_before':{'88':int(b88),'89':int(b89)},
  'http_after':{'88':int(a88),'89':int(a89)},
  'repaired_ids':[88,89],
  'secrets_disclosed':False,
}
with open(out,'w',encoding='utf-8') as fh:
  json.dump(payload,fh,ensure_ascii=False,indent=2,sort_keys=True); fh.write('\n')
PY
}

block() {
  local item="$1"
  write_payload "BLOCKED" "$item"
  echo "[share-index-repair] BLOCKED: $item" >&2
  exit 1
}

cd "$REPO"
PHASE="repo_sync"
[ -z "$(git status --porcelain)" ] || block "production_repo_dirty"
git fetch --prune origin
git checkout main >/dev/null 2>&1
git reset --hard origin/main >/dev/null
[ -s scripts/backup.sh ] || block "backup_script_missing"
[ -s scripts/seo/generate_sitemap.php ] || block "sitemap_script_missing"
[ -s "$WEBROOT/config/database.php" ] || block "db_config_missing"

PHASE="http_before"
BEFORE_88=$(curl -skL --max-time 20 -o /dev/null -w '%{http_code}' "$CANONICAL/index.php?c=show&id=88")
BEFORE_89=$(curl -skL --max-time 20 -o /dev/null -w '%{http_code}' "$CANONICAL/index.php?c=show&id=89")
[ "$BEFORE_88" = 404 ] || block "id88_not_expected_404"
[ "$BEFORE_89" = 404 ] || block "id89_not_expected_404"

PHASE="database_preflight"
PREFLIGHT=$(php -r '
$db=[]; require $argv[1]; $c=$db["default"]??[]; $database=(string)($c["database"]??"");
$pdo=new PDO("mysql:host=".$c["hostname"].";dbname=".$database.";charset=utf8mb4",$c["username"],$c["password"],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC]);
$cols=$pdo->query("SELECT column_name FROM information_schema.columns WHERE table_schema=".$pdo->quote($database)." AND table_name=\"dr_1_share_index\" ORDER BY ordinal_position")->fetchAll(PDO::FETCH_COLUMN);
if ($cols!==["id","mid"]) { echo json_encode(["ok"=>false,"reason"=>"share_index_schema"]); exit; }
$ids=[88,89];
$missing=[]; $existing=[]; $complete=[];
foreach ($ids as $id) {
 $s=$pdo->prepare("SELECT mid FROM dr_1_share_index WHERE id=:id LIMIT 1"); $s->execute([":id"=>$id]); $mid=$s->fetchColumn();
 if ($mid!==false) $existing[(string)$id]=(string)$mid; else $missing[]=$id;
 $q=$pdo->prepare("SELECT COUNT(*) FROM dr_1_news n INNER JOIN dr_1_news_index i ON i.id=n.id INNER JOIN dr_1_news_data_0 d ON d.id=n.id INNER JOIN dr_1_news_hits h ON h.id=n.id WHERE n.id=:id AND n.status=9 AND i.status=9");
 $q->execute([":id"=>$id]); $complete[(string)$id]=(int)$q->fetchColumn();
}
$tables=$pdo->query("SELECT table_name FROM information_schema.tables WHERE table_schema=".$pdo->quote($database)." AND table_name LIKE \"dr_1_%_index\" ORDER BY table_name")->fetchAll(PDO::FETCH_COLUMN);
$collisions=[];
foreach ($tables as $table) {
 if ($table==="dr_1_news_index" || $table==="dr_1_share_index") continue;
 if (!preg_match("/^[A-Za-z0-9_]+$/",$table)) continue;
 $sql="SELECT id FROM `".$table."` WHERE id IN (88,89) ORDER BY id";
 foreach ($pdo->query($sql)->fetchAll(PDO::FETCH_COLUMN) as $id) $collisions[]=["table"=>$table,"id"=>(int)$id];
}
$ai=$pdo->query("SELECT AUTO_INCREMENT FROM information_schema.tables WHERE table_schema=".$pdo->quote($database)." AND table_name=\"dr_1_share_index\"")->fetchColumn();
$ok=count($missing)===2 && !$existing && ($complete["88"]??0)===1 && ($complete["89"]??0)===1 && !$collisions;
echo json_encode(["ok"=>$ok,"missing"=>$missing,"existing"=>$existing,"complete"=>$complete,"collision_count"=>count($collisions),"auto_increment"=>$ai===false?null:(int)$ai]);
' "$WEBROOT/config/database.php")
PREFLIGHT_OK=$(printf '%s' "$PREFLIGHT" | php -r '$x=json_decode(stream_get_contents(STDIN),true); echo !empty($x["ok"])?"1":"0";')
[ "$PREFLIGHT_OK" = 1 ] || block "database_preflight_failed"
COLLISION_COUNT=$(printf '%s' "$PREFLIGHT" | php -r '$x=json_decode(stream_get_contents(STDIN),true); echo (int)($x["collision_count"]??-1);')
[ "$COLLISION_COUNT" -eq 0 ] || block "cross_module_id_collision"

PHASE="backup"
BACKUP_ID=$(date +%Y%m%d_%H%M%S)
XYPTDQ_BACKUP_ID="$BACKUP_ID" XYPTDQ_WEBROOT="$WEBROOT" XYPTDQ_REPO_DIR="$REPO" bash scripts/backup.sh >/dev/null
BACKUP_DIR="/root/backups/deploy_$BACKUP_ID"
[ -s "$BACKUP_DIR/checksums.sha256" ] || block "backup_manifest_missing"
(cd "$BACKUP_DIR" && sha256sum -c checksums.sha256 >/dev/null) || block "backup_checksum_failed"
BACKUP_VERIFY="PASS"

PHASE="share_index_insert"
php -r '
$db=[]; require $argv[1]; $c=$db["default"]??[];
$pdo=new PDO("mysql:host=".$c["hostname"].";dbname=".$c["database"].";charset=utf8mb4",$c["username"],$c["password"],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_EMULATE_PREPARES=>false]);
$pdo->beginTransaction();
try {
 foreach ([88,89] as $id) {
  $s=$pdo->prepare("SELECT mid FROM dr_1_share_index WHERE id=:id FOR UPDATE"); $s->execute([":id"=>$id]);
  if ($s->fetchColumn()!==false) throw new RuntimeException("id already mapped");
  $i=$pdo->prepare("INSERT INTO dr_1_share_index(id,mid) VALUES(:id,:mid)"); $i->execute([":id"=>$id,":mid"=>"news"]);
 }
 $pdo->commit();
} catch (Throwable $e) { if ($pdo->inTransaction()) $pdo->rollBack(); exit(1); }
' "$WEBROOT/config/database.php" || block "share_index_insert_failed"
REPAIR="PASS"

compensate() {
  php -r '
  $db=[]; require $argv[1]; $c=$db["default"]??[];
  $pdo=new PDO("mysql:host=".$c["hostname"].";dbname=".$c["database"].";charset=utf8mb4",$c["username"],$c["password"],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);
  $s=$pdo->prepare("DELETE FROM dr_1_share_index WHERE id IN (88,89) AND mid=:mid"); $s->execute([":mid"=>"news"]);
  ' "$WEBROOT/config/database.php" >/dev/null 2>&1 || true
  XYPTDQ_WEBROOT="$WEBROOT" XYPTDQ_DB_CONFIG="$WEBROOT/config/database.php" XYPTDQ_SITEMAP="$WEBROOT/sitemap.xml" php scripts/seo/generate_sitemap.php >/dev/null 2>&1 || true
}

PHASE="http_after"
AFTER_88=$(curl -skL --max-time 30 -o /dev/null -w '%{http_code}' "$CANONICAL/index.php?c=show&id=88")
AFTER_89=$(curl -skL --max-time 30 -o /dev/null -w '%{http_code}' "$CANONICAL/index.php?c=show&id=89")
if [ "$AFTER_88" != 200 ] || [ "$AFTER_89" != 200 ]; then
  compensate
  REPAIR="ROLLED_BACK"
  block "article_http_failed_after_mapping"
fi

PHASE="post_verify"
POST=$(php -r '
$db=[]; require $argv[1]; $c=$db["default"]??[]; $database=(string)($c["database"]??"");
$pdo=new PDO("mysql:host=".$c["hostname"].";dbname=".$database.";charset=utf8mb4",$c["username"],$c["password"],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC]);
$s=$pdo->query("SELECT id,mid FROM dr_1_share_index WHERE id IN (88,89) ORDER BY id")->fetchAll();
$ai=$pdo->query("SELECT AUTO_INCREMENT FROM information_schema.tables WHERE table_schema=".$pdo->quote($database)." AND table_name=\"dr_1_share_index\"")->fetchColumn();
$ok=count($s)===2 && (int)$s[0]["id"]===88 && $s[0]["mid"]==="news" && (int)$s[1]["id"]===89 && $s[1]["mid"]==="news" && (int)$ai>=90;
echo json_encode(["ok"=>$ok,"auto_increment"=>(int)$ai]);
' "$WEBROOT/config/database.php")
POST_OK=$(printf '%s' "$POST" | php -r '$x=json_decode(stream_get_contents(STDIN),true); echo !empty($x["ok"])?"1":"0";')
AI_AFTER=$(printf '%s' "$POST" | php -r '$x=json_decode(stream_get_contents(STDIN),true); echo (int)($x["auto_increment"]??0);')
if [ "$POST_OK" != 1 ]; then
  compensate
  REPAIR="ROLLED_BACK"
  block "post_verify_failed"
fi

PHASE="sitemap"
XYPTDQ_WEBROOT="$WEBROOT" XYPTDQ_DB_CONFIG="$WEBROOT/config/database.php" XYPTDQ_SITEMAP="$WEBROOT/sitemap.xml" php scripts/seo/generate_sitemap.php >/dev/null || block "sitemap_generation_failed"
for id in 88 89; do
  grep -Eq "id(=|&amp;=)$id([<&]|$)" "$WEBROOT/sitemap.xml" || block "sitemap_missing_repaired_article"
done
SITEMAP="PASS"

PHASE="final"
write_payload "PASS" "NONE"
echo "SHARE_INDEX_SMOKE_REPAIR=PASS ids=88,89 auto_increment=$AI_AFTER"
