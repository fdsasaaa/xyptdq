#!/bin/bash
# Controlled production smoke using Xunrui CMS's native Content::save_content
# lifecycle. Installs a CLI-only API shim temporarily, backs up production first,
# publishes at most one fixture, verifies HTTP/sitemap/registry, then removes the shim.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
CANONICAL="https://www.laocaimi.org"
FIXTURE="content/smoke/native-cms-lifecycle-v1.json"
ENTRY_SRC="scripts/content/native_api/xyptdq.php"
HANDLER_SRC="scripts/content/native_api/Xyptdq.php"
ENTRY_DST="$WEBROOT/api/xyptdq.php"
HANDLER_DST="$WEBROOT/dayrui/My/Api/Xyptdq.php"
PHASE="init"
CMS_ID=0
ARTICLE_HTTP=0
BACKUP_VERIFY=NO
REGISTRY=NO
SITEMAP=NO
NATIVE_SAVE=NO

[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3
[ -d "$WEBROOT" ] || exit 4

write_payload() {
  local status="$1"
  local blocker="$2"
  python3 - "$RESULT_FILE" "$status" "$blocker" "$PHASE" "$CMS_ID" "$ARTICLE_HTTP" \
    "$BACKUP_VERIFY" "$REGISTRY" "$SITEMAP" "$NATIVE_SAVE" <<'PY'
import json,sys
(out,status,blocker,phase,cms_id,http,backup,registry,sitemap,native_save)=sys.argv[1:]
payload={
  'task':'native_cms_publish_smoke',
  'native_cms_publish':status,
  'phase':phase,
  'blocking_item':blocker,
  'cms_id':int(cms_id),
  'article_http':int(http),
  'backup_verification':backup,
  'registry_idempotency':registry,
  'sitemap_contains_article':sitemap,
  'native_save_content':native_save,
  'secrets_disclosed':False,
}
with open(out,'w',encoding='utf-8') as fh:
    json.dump(payload,fh,ensure_ascii=False,indent=2,sort_keys=True); fh.write('\n')
PY
}

block() {
  local item="$1"
  write_payload "BLOCKED" "$item"
  echo "[native-smoke] BLOCKED: $item" >&2
  exit 1
}

cleanup() {
  rm -f "$ENTRY_DST" "$HANDLER_DST" 2>/dev/null || true
}
trap cleanup EXIT

cd "$REPO"
PHASE="repo_sync"
if [ -n "$(git status --porcelain)" ]; then
  block "production_repo_dirty"
fi
git fetch --prune origin
git checkout main >/dev/null 2>&1
git reset --hard origin/main >/dev/null
for f in "$FIXTURE" "$ENTRY_SRC" "$HANDLER_SRC" scripts/backup.sh scripts/seo/generate_sitemap.php scripts/content/cms_publish_adapter.php; do
  [ -s "$f" ] || block "required_source_missing"
done
php -l "$ENTRY_SRC" >/dev/null
php -l "$HANDLER_SRC" >/dev/null

PHASE="fixture"
ARTICLE_KEY=$(php -r '$x=json_decode(file_get_contents($argv[1]),true); echo $x["article_key"]??"";' "$FIXTURE")
TITLE=$(php -r '$x=json_decode(file_get_contents($argv[1]),true); echo $x["title"]??"";' "$FIXTURE")
CATID=$(php -r '$x=json_decode(file_get_contents($argv[1]),true); echo (int)($x["catid"]??0);' "$FIXTURE")
CONTENT_HASH=$(php -r 'require $argv[1]; $x=json_decode(file_get_contents($argv[2]),true); echo xyptdq_article_hash($x);' scripts/content/cms_publish_adapter.php "$FIXTURE")
[[ "$ARTICLE_KEY" =~ ^[a-z0-9][a-z0-9_-]{2,79}$ ]] || block "article_key_invalid"
[ -n "$TITLE" ] || block "title_missing"
[ "$CATID" -gt 0 ] || block "catid_invalid"
[[ "$CONTENT_HASH" =~ ^[0-9a-f]{64}$ ]] || block "content_hash_invalid"

# If this exact fixture was already finalized, prove it instead of republishing.
PHASE="registry_preflight"
EXISTING_ID=$(ARTICLE_KEY="$ARTICLE_KEY" php -r '
$db=[]; require $argv[1]; $c=$db["default"]??[];
$pdo=new PDO("mysql:host=".$c["hostname"].";dbname=".$c["database"].";charset=utf8mb4",$c["username"],$c["password"],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);
$s=$pdo->prepare("SELECT cms_id FROM dr_xyptdq_publish_registry WHERE article_key=:k LIMIT 1");
$s->execute([":k"=>getenv("ARTICLE_KEY")]); echo (int)$s->fetchColumn();
' "$WEBROOT/config/database.php")
if [ "$EXISTING_ID" -gt 0 ]; then
  CMS_ID="$EXISTING_ID"
  ARTICLE_HTTP=$(curl -skL --max-time 30 -o /dev/null -w '%{http_code}' "$CANONICAL/index.php?c=show&id=$CMS_ID")
  [ "$ARTICLE_HTTP" = 200 ] || block "existing_registry_article_not_public"
  REGISTRY=PASS
  NATIVE_SAVE=ALREADY_REGISTERED
else
  # Crash-recovery guard: a prior native save may have completed before registry insert.
  TITLE_ID=$(TITLE="$TITLE" php -r '
$db=[]; require $argv[1]; $c=$db["default"]??[];
$pdo=new PDO("mysql:host=".$c["hostname"].";dbname=".$c["database"].";charset=utf8mb4",$c["username"],$c["password"],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);
$s=$pdo->prepare("SELECT id FROM dr_1_news WHERE title=:t ORDER BY id DESC LIMIT 2");
$s->execute([":t"=>getenv("TITLE")]); $x=$s->fetchAll(PDO::FETCH_COLUMN); echo count($x)===1?(int)$x[0]:0;
' "$WEBROOT/config/database.php")
  if [ "$TITLE_ID" -gt 0 ]; then
    ARTICLE_HTTP=$(curl -skL --max-time 30 -o /dev/null -w '%{http_code}' "$CANONICAL/index.php?c=show&id=$TITLE_ID")
    [ "$ARTICLE_HTTP" = 200 ] || block "preexisting_title_not_public"
    CMS_ID="$TITLE_ID"
    NATIVE_SAVE=RECOVERED_EXISTING
  else
    PHASE="backup"
    BACKUP_ID=$(date +%Y%m%d_%H%M%S)
    XYPTDQ_BACKUP_ID="$BACKUP_ID" XYPTDQ_WEBROOT="$WEBROOT" XYPTDQ_REPO_DIR="$REPO" \
      bash scripts/backup.sh >/dev/null
    BACKUP_DIR="/root/backups/deploy_$BACKUP_ID"
    [ -s "$BACKUP_DIR/checksums.sha256" ] || block "backup_manifest_missing"
    (cd "$BACKUP_DIR" && sha256sum -c checksums.sha256 >/dev/null) || block "backup_checksum_failed"
    BACKUP_VERIFY=PASS

    PHASE="install_cli_shim"
    [ ! -e "$ENTRY_DST" ] || block "api_entry_already_exists"
    [ ! -e "$HANDLER_DST" ] || block "api_handler_already_exists"
    mkdir -p "$(dirname "$ENTRY_DST")" "$(dirname "$HANDLER_DST")"
    cp "$ENTRY_SRC" "$ENTRY_DST"
    cp "$HANDLER_SRC" "$HANDLER_DST"
    chown root:root "$ENTRY_DST" "$HANDLER_DST"
    chmod 0644 "$ENTRY_DST" "$HANDLER_DST"
    [ "$(sha256sum "$ENTRY_SRC" | awk '{print $1}')" = "$(sha256sum "$ENTRY_DST" | awk '{print $1}')" ] || block "api_entry_copy_mismatch"
    [ "$(sha256sum "$HANDLER_SRC" | awk '{print $1}')" = "$(sha256sum "$HANDLER_DST" | awk '{print $1}')" ] || block "api_handler_copy_mismatch"

    PHASE="native_save_content"
    RAW=$(mktemp /tmp/xyptdq-native-cms.XXXXXX.log)
    set +e
    XYPTDQ_NATIVE_ARTICLE_FILE="$REPO/$FIXTURE" \
    XYPTDQ_REPO_CONTENT_ROOT="$REPO/content" \
      php "$ENTRY_DST" >"$RAW" 2>&1
    NATIVE_RC=$?
    set -e
    LINE=$(grep '^XYPTDQ_NATIVE_RESULT=' "$RAW" | tail -n 1 || true)
    rm -f "$RAW"
    [ "$NATIVE_RC" -eq 0 ] || block "native_api_exit_nonzero"
    [ -n "$LINE" ] || block "native_api_result_missing"
    ENCODED="${LINE#XYPTDQ_NATIVE_RESULT=}"
    RESULT_JSON=$(printf '%s' "$ENCODED" | base64 -d 2>/dev/null || true)
    OK=$(printf '%s' "$RESULT_JSON" | php -r '$x=json_decode(stream_get_contents(STDIN),true); echo !empty($x["ok"])?"1":"0";')
    [ "$OK" = 1 ] || block "native_save_content_failed"
    CMS_ID=$(printf '%s' "$RESULT_JSON" | php -r '$x=json_decode(stream_get_contents(STDIN),true); echo (int)($x["cms_id"]??0);')
    [ "$CMS_ID" -gt 0 ] || block "native_cms_id_invalid"
    NATIVE_SAVE=PASS
    cleanup
  fi

  PHASE="article_http"
  ARTICLE_HTTP=$(curl -skL --max-time 30 -o /dev/null -w '%{http_code}' "$CANONICAL/index.php?c=show&id=$CMS_ID")
  [ "$ARTICLE_HTTP" = 200 ] || block "native_article_http_not_200"

  PHASE="registry_commit"
  ARTICLE_KEY="$ARTICLE_KEY" CMS_ID="$CMS_ID" CONTENT_HASH="$CONTENT_HASH" SOURCE_FILE="$FIXTURE" php -r '
$db=[]; require $argv[1]; $c=$db["default"]??[];
$pdo=new PDO("mysql:host=".$c["hostname"].";dbname=".$c["database"].";charset=utf8mb4",$c["username"],$c["password"],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_EMULATE_PREPARES=>false]);
$pdo->beginTransaction();
try {
 $s=$pdo->prepare("SELECT article_key,cms_id,content_hash FROM dr_xyptdq_publish_registry WHERE article_key=:k FOR UPDATE");
 $s->execute([":k"=>getenv("ARTICLE_KEY")]); $row=$s->fetch(PDO::FETCH_ASSOC);
 if ($row) {
   if ((int)$row["cms_id"] !== (int)getenv("CMS_ID") || !hash_equals((string)$row["content_hash"], getenv("CONTENT_HASH"))) throw new RuntimeException("registry conflict");
 } else {
   $i=$pdo->prepare("INSERT INTO dr_xyptdq_publish_registry(article_key,cms_id,content_hash,source_file,published_at) VALUES(:k,:id,:h,:f,:t)");
   $i->execute([":k"=>getenv("ARTICLE_KEY"),":id"=>(int)getenv("CMS_ID"),":h"=>getenv("CONTENT_HASH"),":f"=>getenv("SOURCE_FILE"),":t"=>time()]);
 }
 $pdo->commit();
} catch (Throwable $e) { if ($pdo->inTransaction()) $pdo->rollBack(); exit(1); }
' "$WEBROOT/config/database.php" || block "registry_commit_failed"
  REGISTRY=PASS
fi

PHASE="sitemap"
XYPTDQ_WEBROOT="$WEBROOT" XYPTDQ_DB_CONFIG="$WEBROOT/config/database.php" XYPTDQ_SITEMAP="$WEBROOT/sitemap.xml" \
  php scripts/seo/generate_sitemap.php >/dev/null
if grep -Eq "(id=|id=amp;|id&amp;=)$CMS_ID|id=$CMS_ID|id&amp;=$CMS_ID" "$WEBROOT/sitemap.xml"; then
  SITEMAP=PASS
else
  # Accept any generated loc containing the exact CMS id as a query value.
  grep -Eq "[?&;]id(=|&amp;=)$CMS_ID([<&]|$)" "$WEBROOT/sitemap.xml" || block "sitemap_missing_native_article"
  SITEMAP=PASS
fi

PHASE="final"
ARTICLE_HTTP=$(curl -skL --max-time 30 -o /dev/null -w '%{http_code}' "$CANONICAL/index.php?c=show&id=$CMS_ID")
[ "$ARTICLE_HTTP" = 200 ] || block "final_article_http_not_200"
write_payload "PASS" "NONE"
echo "NATIVE_CMS_PUBLISH_SMOKE=PASS cms_id=$CMS_ID"
