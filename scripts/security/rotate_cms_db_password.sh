#!/bin/bash
# ============================================================
# rotate_cms_db_password.sh
# Safely rotate the Xunrui CMS application database password on MariaDB 10.3.
#
# Default: preflight only.
# Apply:   ./scripts/security/rotate_cms_db_password.sh --apply
#
# Secret values are never printed. A root-only temporary rollback bundle is
# created during rotation and deleted after successful verification.
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

fail() {
    echo "[db-rotate] ERROR: $*" >&2
    exit 1
}

[ -f "$DB_CONFIG" ] || fail "database config not found: $DB_CONFIG"
command -v php >/dev/null 2>&1 || fail "php not found"
command -v mysql >/dev/null 2>&1 || fail "mysql client not found"
command -v openssl >/dev/null 2>&1 || fail "openssl not found"
command -v curl >/dev/null 2>&1 || fail "curl not found"

# Resolve non-secret connection metadata only.
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

# Map the application's connection hostname to the account Host that MariaDB
# actually authenticates. Do not silently guess if there is no matching account.
PREFERRED_ACCOUNT_HOST="$DB_HOST"
if [ "$DB_HOST" = "localhost" ]; then
    PREFERRED_ACCOUNT_HOST="localhost"
elif [ "$DB_HOST" = "127.0.0.1" ]; then
    PREFERRED_ACCOUNT_HOST="127.0.0.1"
fi

ACCOUNT_ROWS=$(mysql --protocol=socket --batch --skip-column-names -e \
    "SELECT Host,COALESCE(plugin,'') FROM mysql.user WHERE User='${DB_USER}' ORDER BY Host;") || \
    fail "cannot query mysql.user through local administrative socket"

[ -n "$ACCOUNT_ROWS" ] || fail "no MariaDB account found for configured CMS user"

ACCOUNT_PLUGIN=""
while IFS=$'\t' read -r host plugin; do
    if [ "$host" = "$PREFERRED_ACCOUNT_HOST" ]; then
        ACCOUNT_PLUGIN="$plugin"
        break
    fi
done <<< "$ACCOUNT_ROWS"

if [ -z "$ACCOUNT_PLUGIN" ]; then
    echo "[db-rotate] Configured DB host: $DB_HOST"
    echo "[db-rotate] Matching MariaDB account host not found; existing account hosts:" >&2
    while IFS=$'\t' read -r host plugin; do
        echo "  - $host (plugin=${plugin:-default})" >&2
    done <<< "$ACCOUNT_ROWS"
    fail "refusing to change a different account host"
fi

case "$ACCOUNT_PLUGIN" in
    ""|mysql_native_password)
        ;;
    *)
        fail "configured application account uses unsupported auth plugin: $ACCOUNT_PLUGIN"
        ;;
esac

# Verify current CMS credentials before changing anything. Password is read only
# inside PHP and never printed.
php -r '
$db=[]; require $argv[1]; $c=$db["default"]??[];
$host=$c["hostname"]??""; $name=$c["database"]??""; $user=$c["username"]??""; $pass=$c["password"]??"";
$pdo=new PDO("mysql:host={$host};dbname={$name};charset=utf8mb4",$user,$pass,[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);
$pdo->query("SELECT 1")->fetchColumn();
' "$DB_CONFIG" || fail "current CMS DB credentials do not connect; fix baseline before rotation"

echo "[db-rotate] PRECHECK PASS user=$DB_USER host=$DB_HOST database=$DB_NAME plugin=${ACCOUNT_PLUGIN:-default}"

if [ "$APPLY" -ne 1 ]; then
    echo "[db-rotate] DRY-RUN ONLY. Re-run with --apply after a fresh backup."
    exit 0
fi

TMPDIR_ROTATE=$(mktemp -d /root/.xyptdq-db-rotate.XXXXXX)
chmod 700 "$TMPDIR_ROTATE"
CONFIG_BACKUP="$TMPDIR_ROTATE/database.php.before"
OLD_PASS_FILE="$TMPDIR_ROTATE/old_password"
NEW_PASS_FILE="$TMPDIR_ROTATE/new_password"
ROLLBACK_NEEDED=1

cleanup() {
    if [ -d "${TMPDIR_ROTATE:-}" ]; then
        rm -rf "$TMPDIR_ROTATE"
    fi
}
trap cleanup EXIT

cp -p "$DB_CONFIG" "$CONFIG_BACKUP"
chmod 600 "$CONFIG_BACKUP"

# Store old secret only in a root-readable temporary file for automatic rollback.
php -r '
$db=[]; require $argv[1]; $c=$db["default"]??[]; $p=(string)($c["password"]??"");
if ($p==="") { fwrite(STDERR,"empty current password\n"); exit(1); }
if (file_put_contents($argv[2],$p,LOCK_EX)===false) exit(2);
chmod($argv[2],0600);
' "$DB_CONFIG" "$OLD_PASS_FILE" || fail "cannot stage rollback credential"

openssl rand -hex 32 > "$NEW_PASS_FILE"
chmod 600 "$NEW_PASS_FILE"
NEW_PASSWORD=$(tr -d '\r\n' < "$NEW_PASS_FILE")
OLD_PASSWORD=$(cat "$OLD_PASS_FILE")
[[ "$NEW_PASSWORD" =~ ^[a-f0-9]{64}$ ]] || fail "generated password failed format invariant"

rollback_rotation() {
    echo "[db-rotate] Verification failed; attempting automatic rollback" >&2
    cp -p "$CONFIG_BACKUP" "$DB_CONFIG"
    chmod 640 "$DB_CONFIG" || true
    # Generated and old passwords are constrained to values that can be safely
    # passed through the SQL literal below; old credential may contain quotes,
    # so escape it with PHP before constructing the SQL file.
    OLD_SQL_ESCAPED=$(php -r 'echo str_replace(["\\","\x27"],["\\\\","\\\x27"],file_get_contents($argv[1]));' "$OLD_PASS_FILE")
    cat > "$TMPDIR_ROTATE/rollback.sql" <<SQL
SET PASSWORD FOR '${DB_USER}'@'${PREFERRED_ACCOUNT_HOST}' = PASSWORD('${OLD_SQL_ESCAPED}');
SQL
    chmod 600 "$TMPDIR_ROTATE/rollback.sql"
    mysql --protocol=socket < "$TMPDIR_ROTATE/rollback.sql" >/dev/null 2>&1 || true
}

# Rotate the MariaDB account first. New password is hex, so SQL literal is safe.
cat > "$TMPDIR_ROTATE/rotate.sql" <<SQL
SET PASSWORD FOR '${DB_USER}'@'${PREFERRED_ACCOUNT_HOST}' = PASSWORD('${NEW_PASSWORD}');
FLUSH PRIVILEGES;
SQL
chmod 600 "$TMPDIR_ROTATE/rotate.sql"
if ! mysql --protocol=socket < "$TMPDIR_ROTATE/rotate.sql" >/dev/null; then
    fail "MariaDB SET PASSWORD failed; application config was not changed"
fi

# Atomically replace only the configured password field. Generated value is hex.
if ! NEW_PASS_FILE="$NEW_PASS_FILE" php -r '
$file=$argv[1]; $new=trim((string)file_get_contents(getenv("NEW_PASS_FILE")));
$src=(string)file_get_contents($file); $count=0;
$dst=preg_replace("/(\x27password\x27\\s*=>\\s*)\x27[^\x27]*\x27/", "$1\x27".$new."\x27", $src, 1, $count);
if ($dst===null || $count!==1) { fwrite(STDERR,"password field replacement invariant failed\n"); exit(3); }
$tmp=$file.".rotate.".getmypid();
if (file_put_contents($tmp,$dst,LOCK_EX)===false) exit(4);
chmod($tmp,0640);
if (!rename($tmp,$file)) { @unlink($tmp); exit(5); }
' "$DB_CONFIG"; then
    rollback_rotation
    fail "CMS config update failed; rollback attempted"
fi

# Validate through the exact CMS config, then through public application paths.
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
if [ "$HOME_CODE" != "200" ] || [ "$ARTICLE_CODE" != "200" ]; then
    rollback_rotation
    fail "HTTP verification failed home=$HOME_CODE article=$ARTICLE_CODE; rollback attempted"
fi

ROLLBACK_NEEDED=0
# The temporary directory (including both password values) is destroyed by trap.
echo "[db-rotate] ROTATED AND VERIFIED"
echo "[db-rotate] home_http=$HOME_CODE article_http=$ARTICLE_CODE"
