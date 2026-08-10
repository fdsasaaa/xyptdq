#!/bin/bash
# ============================================================
# rotate_cms_db_password.sh
# Safely rotate the Xunrui CMS application DB password on MariaDB 10.3.
#
# Default: preflight only.
# Apply:   ./scripts/security/rotate_cms_db_password.sh --apply
#
# Secrets are never printed. A root-only rollback bundle exists only for the
# duration of the operation and is destroyed on exit.
# ============================================================
set -euo pipefail

APPLY=0
if [ "${1:-}" = "--apply" ]; then
    APPLY=1
elif [ -n "${1:-}" ]; then
    echo "Usage: $0 [--apply]" >&2
    exit 2
fi

WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
DB_CONFIG="${XYPTDQ_DB_CONFIG:-$WEBROOT/config/database.php}"
KNOWN_ARTICLE_URL="${XYPTDQ_KNOWN_ARTICLE_URL:-https://www.laocaimi.org/index.php?c=show&id=47}"
HOME_URL="${XYPTDQ_HOME_URL:-https://www.laocaimi.org/}"
FPM_SERVICE="${XYPTDQ_PHP_FPM_SERVICE:-php7.4-fpm}"

fail() {
    echo "[db-rotate] ERROR: $*" >&2
    exit 1
}

[ -f "$DB_CONFIG" ] || fail "database config not found: $DB_CONFIG"
for cmd in php mysql openssl curl systemctl; do
    command -v "$cmd" >/dev/null 2>&1 || fail "$cmd not found"
done
systemctl is-active --quiet "$FPM_SERVICE" || fail "PHP-FPM service is not active: $FPM_SERVICE"

# Resolve only non-secret connection metadata.
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
    echo "[db-rotate] configured account host has no exact MariaDB match" >&2
    fail "refusing to rotate a different MariaDB account host"
fi
case "$ACCOUNT_PLUGIN" in
    ""|mysql_native_password) ;;
    *) fail "unsupported application auth plugin: $ACCOUNT_PLUGIN" ;;
esac

# Baseline DB test through the exact CMS config.
php -r '
$db=[]; require $argv[1]; $c=$db["default"]??[];
$pdo=new PDO("mysql:host=".$c["hostname"].";dbname=".$c["database"].";charset=utf8mb4",$c["username"],$c["password"],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);
$pdo->query("SELECT 1")->fetchColumn();
' "$DB_CONFIG" || fail "current CMS DB credentials do not connect"

# Capture HTTP baseline BEFORE changing credentials. A pre-existing 500 must not
# be misdiagnosed as a rotation failure.
BASE_HOME=$(curl -sk -o /dev/null -w '%{http_code}' "$HOME_URL")
BASE_ARTICLE=$(curl -sk -o /dev/null -w '%{http_code}' "$KNOWN_ARTICLE_URL")
if [ "$BASE_HOME" != "200" ] || [ "$BASE_ARTICLE" != "200" ]; then
    fail "baseline HTTP is not healthy home=$BASE_HOME article=$BASE_ARTICLE"
fi

echo "[db-rotate] PRECHECK PASS user=$DB_USER host=$DB_HOST database=$DB_NAME plugin=${ACCOUNT_PLUGIN:-default} home=200 article=200"
if [ "$APPLY" -ne 1 ]; then
    echo "[db-rotate] DRY-RUN ONLY. Re-run with --apply after a fresh backup."
    exit 0
fi

TMPDIR_ROTATE=$(mktemp -d /root/.xyptdq-db-rotate.XXXXXX)
chmod 700 "$TMPDIR_ROTATE"
CONFIG_BACKUP="$TMPDIR_ROTATE/database.php.before"
OLD_PASS_FILE="$TMPDIR_ROTATE/old_password"
NEW_PASS_FILE="$TMPDIR_ROTATE/new_password"

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

reload_fpm() {
    systemctl reload "$FPM_SERVICE" >/dev/null 2>&1
}

rollback_rotation() {
    echo "[db-rotate] Verification failed; attempting automatic rollback" >&2
    cp -p "$CONFIG_BACKUP" "$DB_CONFIG"
    chmod 640 "$DB_CONFIG" || true
    OLD_SQL_ESCAPED=$(php -r 'echo str_replace(["\\","\x27"],["\\\\","\\\x27"],file_get_contents($argv[1]));' "$OLD_PASS_FILE")
    cat > "$TMPDIR_ROTATE/rollback.sql" <<SQL
SET PASSWORD FOR '${DB_USER}'@'${PREFERRED_ACCOUNT_HOST}' = PASSWORD('${OLD_SQL_ESCAPED}');
FLUSH PRIVILEGES;
SQL
    chmod 600 "$TMPDIR_ROTATE/rollback.sql"
    mysql --protocol=socket < "$TMPDIR_ROTATE/rollback.sql" >/dev/null 2>&1 || true
    reload_fpm || true
}

cat > "$TMPDIR_ROTATE/rotate.sql" <<SQL
SET PASSWORD FOR '${DB_USER}'@'${PREFERRED_ACCOUNT_HOST}' = PASSWORD('${NEW_PASSWORD}');
FLUSH PRIVILEGES;
SQL
chmod 600 "$TMPDIR_ROTATE/rotate.sql"
if ! mysql --protocol=socket < "$TMPDIR_ROTATE/rotate.sql" >/dev/null; then
    fail "MariaDB SET PASSWORD failed; application config was not changed"
fi

# Replace exactly one quoted PHP password value. The generated value is hex.
if ! NEW_PASS_FILE="$NEW_PASS_FILE" php -r '
$file=$argv[1]; $new=trim((string)file_get_contents(getenv("NEW_PASS_FILE")));
$src=(string)file_get_contents($file); $count=0;
$dst=preg_replace("/(\x27password\x27\\s*=>\\s*)\x27[^\x27]*\x27/", "$1\x27".$new."\x27", $src, 1, $count);
if ($dst===null || $count!==1) exit(3);
$tmp=$file.".rotate.".getmypid();
if (file_put_contents($tmp,$dst,LOCK_EX)===false) exit(4);
chmod($tmp,0640);
if (!rename($tmp,$file)) { @unlink($tmp); exit(5); }
' "$DB_CONFIG"; then
    rollback_rotation
    fail "CMS config update failed; rollback attempted"
fi

# PHP-FPM workers may retain opcache/config state. Reload them before HTTP tests.
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

HOME_CODE=$(curl -sk -o /dev/null -w '%{http_code}' "$HOME_URL")
ARTICLE_CODE=$(curl -sk -o /dev/null -w '%{http_code}' "$KNOWN_ARTICLE_URL")
if [ "$HOME_CODE" != "$BASE_HOME" ] || [ "$ARTICLE_CODE" != "$BASE_ARTICLE" ]; then
    rollback_rotation
    fail "HTTP changed after rotation baseline=${BASE_HOME}/${BASE_ARTICLE} post=${HOME_CODE}/${ARTICLE_CODE}; rollback attempted"
fi

echo "[db-rotate] ROTATED AND VERIFIED"
echo "[db-rotate] home_http=$HOME_CODE article_http=$ARTICLE_CODE fpm_reload=PASS"
