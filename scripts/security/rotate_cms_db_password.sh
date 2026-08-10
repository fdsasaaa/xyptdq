#!/bin/bash
# ============================================================
# rotate_cms_db_password.sh
# Fail-safe Xunrui CMS database password rotation for MariaDB 10.3.
#
# Default: dry-run/preflight only.
# Apply:   bash scripts/security/rotate_cms_db_password.sh --apply
# ============================================================
set -euo pipefail

APPLY=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --apply) APPLY=1 ;;
        --dry-run) APPLY=0 ;;
        -h|--help)
            echo "Usage: $0 [--dry-run|--apply]"
            exit 0
            ;;
        *)
            echo "Usage: $0 [--dry-run|--apply]" >&2
            echo "[db-rotate] ERROR: unknown argument: $1" >&2
            exit 2
            ;;
    esac
    shift
done

WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
DB_CONFIG="${XYPTDQ_DB_CONFIG:-$WEBROOT/config/database.php}"
KNOWN_ARTICLE_URL="${XYPTDQ_KNOWN_ARTICLE_URL:-https://www.laocaimi.org/index.php?c=show&id=47}"
HOME_URL="${XYPTDQ_HOME_URL:-https://www.laocaimi.org/}"
FPM_SERVICE="${XYPTDQ_PHP_FPM_SERVICE:-php7.4-fpm}"

fail() {
    echo "[db-rotate] ERROR: $*" >&2
    exit 1
}

http_code() {
    curl -sk --max-time 20 -o /dev/null -w '%{http_code}' "$1"
}

reload_fpm() {
    systemctl reload "$FPM_SERVICE" >/dev/null 2>&1
}

[ -f "$DB_CONFIG" ] || fail "database config not found: $DB_CONFIG"
for cmd in php mysql openssl curl systemctl stat; do
    command -v "$cmd" >/dev/null 2>&1 || fail "$cmd not found"
done
systemctl is-active --quiet "$FPM_SERVICE" || fail "PHP-FPM service is not active: $FPM_SERVICE"

META=$(php -r '
$db=[]; require $argv[1]; $c=$db["default"]??[];
$out=["hostname"=>$c["hostname"]??"","username"=>$c["username"]??"","database"=>$c["database"]??""];
echo json_encode($out, JSON_UNESCAPED_SLASHES);
' "$DB_CONFIG")
DB_HOST=$(php -r '$x=json_decode($argv[1],true); echo $x["hostname"]??"";' "$META")
DB_USER=$(php -r '$x=json_decode($argv[1],true); echo $x["username"]??"";' "$META")
DB_NAME=$(php -r '$x=json_decode($argv[1],true); echo $x["database"]??"";' "$META")

[[ "$DB_USER" =~ ^[A-Za-z0-9_.-]+$ ]] || fail "unexpected DB username format"
[[ "$DB_NAME" =~ ^[A-Za-z0-9_]+$ ]] || fail "unexpected DB name format"
[[ "$DB_HOST" =~ ^[A-Za-z0-9_.:-]+$ ]] || fail "unexpected DB hostname format"

PREFERRED_ACCOUNT_HOST="$DB_HOST"
ACCOUNT_ROWS=$(mysql --protocol=socket --batch --skip-column-names -e \
    "SELECT Host,COALESCE(plugin,'') FROM mysql.user WHERE User='${DB_USER}' ORDER BY Host;") || \
    fail "cannot query mysql.user through local administrative socket"
[ -n "$ACCOUNT_ROWS" ] || fail "no MariaDB account found for configured CMS user"

ACCOUNT_FOUND=0
ACCOUNT_PLUGIN=""
while IFS=$'\t' read -r host plugin; do
    if [ "$host" = "$PREFERRED_ACCOUNT_HOST" ]; then
        ACCOUNT_FOUND=1
        ACCOUNT_PLUGIN="$plugin"
        break
    fi
done <<< "$ACCOUNT_ROWS"

if [ "$ACCOUNT_FOUND" -ne 1 ]; then
    echo "[db-rotate] configured_host=$DB_HOST matching_account=NOT_FOUND" >&2
    echo "[db-rotate] available account hosts:" >&2
    while IFS=$'\t' read -r host plugin; do
        echo "  - $host (plugin=${plugin:-default})" >&2
    done <<< "$ACCOUNT_ROWS"
    fail "refusing to rotate a different MariaDB account host"
fi
case "$ACCOUNT_PLUGIN" in
    ""|mysql_native_password) ;;
    *) fail "unsupported application auth plugin: $ACCOUNT_PLUGIN" ;;
esac

php -r '
$db=[]; require $argv[1]; $c=$db["default"]??[];
$pdo=new PDO("mysql:host=".$c["hostname"].";dbname=".$c["database"].";charset=utf8mb4",$c["username"],$c["password"],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);
$pdo->query("SELECT 1")->fetchColumn();
' "$DB_CONFIG" || fail "current CMS DB credentials do not connect"

BASE_HOME=$(http_code "$HOME_URL")
BASE_ARTICLE=$(http_code "$KNOWN_ARTICLE_URL")
[ "$BASE_HOME" = "200" ] || fail "baseline homepage HTTP is $BASE_HOME, expected 200"
[ "$BASE_ARTICLE" = "200" ] || fail "baseline article HTTP is $BASE_ARTICLE, expected 200"

MODE="DRY_RUN"
[ "$APPLY" -eq 1 ] && MODE="APPLY"
echo "[db-rotate] PRECHECK PASS user=$DB_USER host=$DB_HOST database=$DB_NAME plugin=${ACCOUNT_PLUGIN:-default} home=200 article=200"
echo "[db-rotate] MODE=$MODE"

if [ "$APPLY" -ne 1 ]; then
    echo "[db-rotate] DRY-RUN ONLY. Re-run with --apply after a verified fresh backup."
    exit 0
fi

echo "[db-rotate] APPLY CONFIRMED"

TMPDIR_ROTATE=$(mktemp -d /root/.xyptdq-db-rotate.XXXXXX)
chmod 700 "$TMPDIR_ROTATE"
CONFIG_BACKUP="$TMPDIR_ROTATE/database.php.before"
OLD_PASS_FILE="$TMPDIR_ROTATE/old_password"
NEW_PASS_FILE="$TMPDIR_ROTATE/new_password"
ORIG_UID=$(stat -c '%u' "$DB_CONFIG")
ORIG_GID=$(stat -c '%g' "$DB_CONFIG")
ORIG_MODE=$(stat -c '%a' "$DB_CONFIG")

cleanup() {
    [ -d "${TMPDIR_ROTATE:-}" ] && rm -rf "$TMPDIR_ROTATE"
}
trap cleanup EXIT

cp -p "$DB_CONFIG" "$CONFIG_BACKUP"
chmod 600 "$CONFIG_BACKUP"
php -r '
$db=[]; require $argv[1]; $c=$db["default"]??[]; $p=(string)($c["password"]??"");
if ($p==="") exit(1);
if (file_put_contents($argv[2],$p,LOCK_EX)===false) exit(2);
chmod($argv[2],0600);
' "$DB_CONFIG" "$OLD_PASS_FILE" || fail "cannot stage rollback credential"

openssl rand -hex 32 > "$NEW_PASS_FILE"
chmod 600 "$NEW_PASS_FILE"
NEW_PASSWORD=$(tr -d '\r\n' < "$NEW_PASS_FILE")
[[ "$NEW_PASSWORD" =~ ^[a-f0-9]{64}$ ]] || fail "generated password failed invariant"
OLD_PASSWORD_HEX=$(php -r 'echo bin2hex(file_get_contents($argv[1]));' "$OLD_PASS_FILE")
[[ "$OLD_PASSWORD_HEX" =~ ^[a-fA-F0-9]+$ ]] || fail "cannot encode rollback credential"

rollback_rotation() {
    echo "[db-rotate] Verification failed; attempting automatic rollback" >&2
    cat > "$TMPDIR_ROTATE/rollback.sql" <<SQL
SET PASSWORD FOR '${DB_USER}'@'${PREFERRED_ACCOUNT_HOST}' = PASSWORD(UNHEX('${OLD_PASSWORD_HEX}'));
FLUSH PRIVILEGES;
SQL
    chmod 600 "$TMPDIR_ROTATE/rollback.sql"
    mysql --protocol=socket < "$TMPDIR_ROTATE/rollback.sql" >/dev/null 2>&1 || true
    cp -p "$CONFIG_BACKUP" "$DB_CONFIG" || true
    reload_fpm || true
    local rh ra
    rh=$(http_code "$HOME_URL" || true)
    ra=$(http_code "$KNOWN_ARTICLE_URL" || true)
    echo "[db-rotate] ROLLBACK_HTTP home=$rh article=$ra" >&2
}

cat > "$TMPDIR_ROTATE/rotate.sql" <<SQL
SET PASSWORD FOR '${DB_USER}'@'${PREFERRED_ACCOUNT_HOST}' = PASSWORD('${NEW_PASSWORD}');
FLUSH PRIVILEGES;
SQL
chmod 600 "$TMPDIR_ROTATE/rotate.sql"
if ! mysql --protocol=socket < "$TMPDIR_ROTATE/rotate.sql" >/dev/null; then
    fail "MariaDB SET PASSWORD failed; application config was not changed"
fi

# Preserve the original owner/group/mode before the atomic rename. The previous
# version created a root-owned 0640 replacement, which can make PHP-FPM unable to
# read database.php and produce HTTP 500 even when the DB password is correct.
if ! NEW_PASS_FILE="$NEW_PASS_FILE" ORIG_UID="$ORIG_UID" ORIG_GID="$ORIG_GID" ORIG_MODE="$ORIG_MODE" php -r '
$file=$argv[1]; $new=trim((string)file_get_contents(getenv("NEW_PASS_FILE")));
$src=(string)file_get_contents($file); $count=0;
$dst=preg_replace("/(\x27password\x27\\s*=>\\s*)\x27[^\x27]*\x27/", "$1\x27".$new."\x27", $src, 1, $count);
if ($dst===null || $count!==1) exit(3);
$tmp=$file.".rotate.".getmypid();
if (file_put_contents($tmp,$dst,LOCK_EX)===false) exit(4);
if (!chown($tmp,(int)getenv("ORIG_UID")) || !chgrp($tmp,(int)getenv("ORIG_GID"))) { @unlink($tmp); exit(5); }
chmod($tmp,octdec((string)getenv("ORIG_MODE")));
if (!rename($tmp,$file)) { @unlink($tmp); exit(6); }
' "$DB_CONFIG"; then
    rollback_rotation
    fail "CMS config update failed; rollback attempted"
fi

if ! reload_fpm; then
    rollback_rotation
    fail "PHP-FPM reload failed after config update; rollback attempted"
fi

if ! php -r '
$db=[]; require $argv[1]; $c=$db["default"]??[];
$pdo=new PDO("mysql:host=".$c["hostname"].";dbname=".$c["database"].";charset=utf8mb4",$c["username"],$c["password"],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);
$pdo->query("SELECT 1")->fetchColumn();
' "$DB_CONFIG"; then
    rollback_rotation
    fail "new CMS DB credential failed connection test; rollback attempted"
fi

sleep 1
HOME_CODE=$(http_code "$HOME_URL")
ARTICLE_CODE=$(http_code "$KNOWN_ARTICLE_URL")
if [ "$HOME_CODE" != "$BASE_HOME" ] || [ "$ARTICLE_CODE" != "$BASE_ARTICLE" ]; then
    rollback_rotation
    fail "HTTP changed after rotation baseline=${BASE_HOME}/${BASE_ARTICLE} post=${HOME_CODE}/${ARTICLE_CODE}; rollback attempted"
fi

[ "$(stat -c '%u' "$DB_CONFIG")" = "$ORIG_UID" ] || { rollback_rotation; fail "config owner changed unexpectedly"; }
[ "$(stat -c '%g' "$DB_CONFIG")" = "$ORIG_GID" ] || { rollback_rotation; fail "config group changed unexpectedly"; }
[ "$(stat -c '%a' "$DB_CONFIG")" = "$ORIG_MODE" ] || { rollback_rotation; fail "config mode changed unexpectedly"; }

echo "[db-rotate] ROTATED AND VERIFIED"
echo "[db-rotate] home_http=$HOME_CODE article_http=$ARTICLE_CODE fpm_reload=PASS"
