#!/bin/bash
# Backup-gated end-to-end smoke for the production native Xunrui adapter.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
CANONICAL="https://www.laocaimi.org"
FIXTURE="content/smoke/native-cms-lifecycle-v2.json"
PHASE="init"
BACKUP="NO"
DRYRUN="NO"
SMOKE="NO"
SECOND_IDEMPOTENT="NO"
ARTICLE_HTTP=0
CMS_ID=0
REGISTRY="NO"
SHARE_INDEX="NO"
SITEMAP="NO"
SHIMS_REMOVED="NO"

[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3
[ -d "$WEBROOT" ] || exit 4

write_payload() {
  local status="$1" blocker="$2"
  python3 - "$RESULT_FILE" "$status" "$blocker" "$PHASE" "$BACKUP" "$DRYRUN" "$SMOKE" "$SECOND_IDEMPOTENT" "$ARTICLE_HTTP" "$CMS_ID" "$REGISTRY" "$SHARE_INDEX" "$SITEMAP" "$SHIMS_REMOVED" <<'PY'
import json,sys
(out,status,blocker,phase,backup,dryrun,smoke,idempotent,http,cms_id,registry,share,sitemap,shims)=sys.argv[1:]
payload={
 'task':'native_adapter_idempotency_smoke',
 'native_adapter_smoke':status,
 'phase':phase,
 'blocking_item':blocker,
 'backup_verification':backup,
 'dry_run_preflight':dryrun,
 'smoke_publish':smoke,
 'second_publish_idempotent':idempotent,
 'cms_id':int(cms_id),
 'article_http':int(http),
 'registry_verification':registry,
 'share_index_verification':share,
 'sitemap_contains_article':sitemap,
 'temporary_cli_shims_removed':shims,
 'secrets_disclosed':False,
}
with open(out,'w',encoding='utf-8') as fh:
 json.dump(payload,fh,ensure_ascii=False,indent=2,sort_keys=True); fh.write('\n')
PY
}
block() { write_payload BLOCKED "$1"; echo "[native-adapter-smoke] BLOCKED: $1" >&2; exit 1; }

cd "$REPO"
PHASE="repo_sync"
[ -z "$(git status --porcelain)" ] || block production_repo_dirty
git fetch --prune origin
git checkout main >/dev/null 2>&1
git reset --hard origin/main >/dev/null
for f in "$FIXTURE" scripts/content/cms_publish_native_adapter.php scripts/content/publisher_native_smoke.php scripts/content/native_api/xyptdq.php scripts/content/native_api/Xyptdq.php scripts/backup.sh scripts/seo/generate_sitemap.php; do
  [ -s "$f" ] || block required_source_missing
done
php -l scripts/content/cms_publish_native_adapter.php >/dev/null
php -l scripts/content/publisher_native_smoke.php >/dev/null

PHASE="legacy_smoke_visibility"
[ "$(curl -skL --max-time 20 -o /dev/null -w '%{http_code}' "$CANONICAL/index.php?c=show&id=88")" = 200 ] || block repaired_id88_not_public
[ "$(curl -skL --max-time 20 -o /dev/null -w '%{http_code}' "$CANONICAL/index.php?c=show&id=89")" = 200 ] || block repaired_id89_not_public

PHASE="dry_run"
DRY_OUT=$(mktemp /tmp/xyptdq-native-dry.XXXXXX)
if ! php scripts/content/publisher_native_smoke.php --article="$FIXTURE" >"$DRY_OUT" 2>&1; then
  rm -f "$DRY_OUT"
  block native_dry_run_failed
fi
grep -Fq 'TARGET_PREFLIGHT PASS' "$DRY_OUT" || { rm -f "$DRY_OUT"; block category_preflight_missing; }
grep -Fq 'ALLOCATOR_PREFLIGHT PASS' "$DRY_OUT" || { rm -f "$DRY_OUT"; block allocator_preflight_missing; }
grep -Fq 'DRY-RUN ONLY' "$DRY_OUT" || { rm -f "$DRY_OUT"; block dry_run_marker_missing; }
rm -f "$DRY_OUT"
DRYRUN="PASS"

PHASE="backup"
BACKUP_ID=$(date +%Y%m%d_%H%M%S)
XYPTDQ_BACKUP_ID="$BACKUP_ID" XYPTDQ_WEBROOT="$WEBROOT" XYPTDQ_REPO_DIR="$REPO" bash scripts/backup.sh >/dev/null
BACKUP_DIR="/root/backups/deploy_$BACKUP_ID"
[ -s "$BACKUP_DIR/checksums.sha256" ] || block backup_manifest_missing
(cd "$BACKUP_DIR" && sha256sum -c checksums.sha256 >/dev/null) || block backup_checksum_failed
BACKUP="PASS"

PHASE="native_commit"
OUT=$(mktemp /tmp/xyptdq-native-smoke.XXXXXX)
set +e
php scripts/content/publisher_native_smoke.php --article="$FIXTURE" --commit >"$OUT" 2>&1
RC=$?
set -e
if [ "$RC" -ne 0 ]; then rm -f "$OUT"; block native_smoke_commit_failed; fi
grep -Fq 'second_idempotent=true' "$OUT" || { rm -f "$OUT"; block second_idempotency_missing; }
LINE=$(grep -F '[publisher-native-smoke] PASS cms_id=' "$OUT" | tail -n1 || true)
CMS_ID=$(printf '%s' "$LINE" | sed -n 's/.*cms_id=\([0-9][0-9]*\).*/\1/p')
rm -f "$OUT"
[ -n "$CMS_ID" ] && [ "$CMS_ID" -ge 90 ] || block native_cms_id_not_above_repaired_allocator
SMOKE="PASS"
SECOND_IDEMPOTENT="YES"

PHASE="http"
ARTICLE_HTTP=$(curl -skL --max-time 30 -o /dev/null -w '%{http_code}' "$CANONICAL/index.php?c=show&id=$CMS_ID")
[ "$ARTICLE_HTTP" = 200 ] || block native_article_http_not_200

PHASE="database_verify"
ARTICLE_KEY=$(php -r '$x=json_decode(file_get_contents($argv[1]),true); echo $x["article_key"]??"";' "$FIXTURE")
EXPECTED_HASH=$(php -r 'require $argv[1]; $x=json_decode(file_get_contents($argv[2]),true); echo xyptdq_native_article_hash($x);' scripts/content/cms_publish_native_adapter.php "$FIXTURE")
VERIFY=$(ARTICLE_KEY="$ARTICLE_KEY" CMS_ID="$CMS_ID" EXPECTED_HASH="$EXPECTED_HASH" php -r '
$db=[]; require $argv[1]; $c=$db["default"]??[];
$pdo=new PDO("mysql:host=".$c["hostname"].";dbname=".$c["database"].";charset=utf8mb4",$c["username"],$c["password"],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC]);
$s=$pdo->prepare("SELECT cms_id,content_hash FROM dr_xyptdq_publish_registry WHERE article_key=:k LIMIT 1"); $s->execute([":k"=>getenv("ARTICLE_KEY")]); $r=$s->fetch()?:[];
$s=$pdo->prepare("SELECT mid FROM dr_1_share_index WHERE id=:id LIMIT 1"); $s->execute([":id"=>(int)getenv("CMS_ID")]); $mid=$s->fetchColumn();
$ai=(int)$pdo->query("SELECT AUTO_INCREMENT FROM information_schema.tables WHERE table_schema=DATABASE() AND table_name=\"dr_1_share_index\"")->fetchColumn();
$ok=(int)($r["cms_id"]??0)===(int)getenv("CMS_ID") && hash_equals((string)($r["content_hash"]??""),getenv("EXPECTED_HASH")) && $mid==="news" && $ai>(int)getenv("CMS_ID");
echo json_encode(["ok"=>$ok,"registry"=>(int)($r["cms_id"]??0)===(int)getenv("CMS_ID"),"share"=>$mid==="news","ai"=>$ai]);
' "$WEBROOT/config/database.php")
VERIFY_OK=$(printf '%s' "$VERIFY" | php -r '$x=json_decode(stream_get_contents(STDIN),true); echo !empty($x["ok"])?"1":"0";')
[ "$VERIFY_OK" = 1 ] || block database_verification_failed
REGISTRY="PASS"
SHARE_INDEX="PASS"

PHASE="sitemap"
XYPTDQ_WEBROOT="$WEBROOT" XYPTDQ_DB_CONFIG="$WEBROOT/config/database.php" XYPTDQ_SITEMAP="$WEBROOT/sitemap.xml" php scripts/seo/generate_sitemap.php >/dev/null || block sitemap_generation_failed
grep -Eq "id(=|&amp;=)$CMS_ID([<&]|$)" "$WEBROOT/sitemap.xml" || block sitemap_missing_native_article
SITEMAP="YES"

PHASE="shim_cleanup"
[ ! -e "$WEBROOT/api/xyptdq.php" ] || block temporary_api_entry_remains
[ ! -e "$WEBROOT/dayrui/My/Api/Xyptdq.php" ] || block temporary_api_handler_remains
SHIMS_REMOVED="YES"

PHASE="final"
write_payload PASS NONE
echo "NATIVE_ADAPTER_IDEMPOTENCY_SMOKE=PASS cms_id=$CMS_ID"
