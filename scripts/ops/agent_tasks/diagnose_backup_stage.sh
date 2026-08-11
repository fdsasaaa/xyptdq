#!/bin/bash
# Diagnose the canonical deploy backup stage without exposing filenames,
# database credentials, database name, or raw stderr. Diagnostic artifacts are
# root-only and deleted before exit.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
CANONICAL="https://www.laocaimi.org"
BACKUP_ROOT="${XYPTDQ_BACKUP_ROOT:-/root/backups}"
EXPECTED_FRAME_LOCK_HEX="436f646549676e697465723732"

[ -n "$RESULT_FILE" ] || exit 2
[ -d "$WEBROOT" ] || exit 3
[ -f "$WEBROOT/config/database.php" ] || exit 4
mkdir -p "$BACKUP_ROOT"

RUN_ID="${XYPTDQ_AGENT_JOB_ID:-diagnose-backup-stage}"
SAFE_ID=$(printf '%s' "$RUN_ID" | tr -cd 'A-Za-z0-9._-')
TMP="$BACKUP_ROOT/.diag_${SAFE_ID}_$$"
mkdir -m 700 "$TMP"
cleanup(){ rm -rf "$TMP"; }
trap cleanup EXIT

TAR_STATUS="NOT_RUN"; TAR_CLASS="NONE"; TAR_BYTES=0
DB_STATUS="NOT_RUN"; DB_CLASS="NONE"; DB_BYTES=0
NGINX_STATUS="NOT_RUN"; CHECKSUM_STATUS="NOT_RUN"
FRAME_LOCK="NO"; CACHE_FACTORY="NO"
HOME_HTTP=0; ARTICLE_HTTP=0; CATEGORY_HTTP=0
BLOCKER="NONE"

classify_tar(){
  local e="$1"
  if grep -Eiq 'file changed as we read it' "$e"; then echo file_changed_as_read
  elif grep -Eiq 'permission denied' "$e"; then echo permission_denied
  elif grep -Eiq 'file removed before we read it|cannot stat.*no such file' "$e"; then echo file_removed_during_read
  elif grep -Eiq 'write error|no space left|file size limit|cannot write' "$e"; then echo archive_write_error
  elif grep -Eiq 'socket ignored|file is the archive; not dumped' "$e"; then echo special_file_warning
  elif [ -s "$e" ]; then echo other_tar_error
  else echo no_stderr_marker
  fi
}

classify_db(){
  local e="$1"
  if grep -Eiq 'access denied|permission denied' "$e"; then echo access_denied
  elif grep -Eiq 'can.t connect|connection refused|unknown mysql server host|server has gone away' "$e"; then echo connection_error
  elif grep -Eiq 'PROCESS privilege|SUPER privilege|LOCK TABLES|TRIGGER|routine|event' "$e"; then echo privilege_or_routine_error
  elif grep -Eiq 'unknown option|ambiguous option|illegal option' "$e"; then echo option_error
  elif [ -s "$e" ]; then echo other_database_error
  else echo no_stderr_marker
  fi
}

# Current production health after previous rollback.
HOME_HTTP=$(curl -skL --max-time 20 -o /dev/null -w '%{http_code}' "$CANONICAL/" || printf 0)
ARTICLE_HTTP=$(curl -skL --max-time 20 -o /dev/null -w '%{http_code}' "$CANONICAL/index.php?c=show&id=91" || printf 0)
CATEGORY_HTTP=$(curl -skL --max-time 20 -o /dev/null -w '%{http_code}' "$CANONICAL/index.php?c=category&id=7" || printf 0)

if [ -f "$WEBROOT/dayrui/CodeIgniter72/System/Cache/CacheFactory.php" ]; then CACHE_FACTORY="YES"; fi
if [ -f "$WEBROOT/cache/frame.lock" ]; then
  HEX=$(od -An -tx1 -v "$WEBROOT/cache/frame.lock" | tr -d ' \n')
  [ "$HEX" = "$EXPECTED_FRAME_LOCK_HEX" ] && FRAME_LOCK="YES" || FRAME_LOCK="INVALID"
fi

# A. Website tar: same inclusion/exclusion model as backup.sh, but diagnose it
# independently and do not publish stderr or file names.
set +e
tar czf "$TMP/website_files.tar.gz" -C "$WEBROOT" --exclude='cache' . 2>"$TMP/tar.err"
TAR_RC=$?
set -e
if [ "$TAR_RC" -eq 0 ] && [ -s "$TMP/website_files.tar.gz" ]; then
  TAR_STATUS="PASS"
  TAR_BYTES=$(stat -c '%s' "$TMP/website_files.tar.gz" 2>/dev/null || printf 0)
else
  TAR_STATUS="FAIL"
  TAR_CLASS=$(classify_tar "$TMP/tar.err")
  BLOCKER="website_tar"
fi

# B. Database dump: only run if website archive passed. Resolve DB name
# internally; never return it in the result payload.
if [ "$TAR_STATUS" = PASS ]; then
  DB_NAME=$(php -r '$db=[]; require $argv[1]; $c=$db["default"]??[]; echo $c["database"]??"";' "$WEBROOT/config/database.php")
  if [ -z "$DB_NAME" ] || ! [[ "$DB_NAME" =~ ^[A-Za-z0-9_]+$ ]]; then
    DB_STATUS="FAIL"; DB_CLASS="invalid_database_identifier"; BLOCKER="database_dump"
  else
    set +e
    mysqldump --single-transaction --routines --triggers "$DB_NAME" >"$TMP/database.sql" 2>"$TMP/db.err"
    DB_RC=$?
    set -e
    if [ "$DB_RC" -eq 0 ] && [ -s "$TMP/database.sql" ]; then
      DB_STATUS="PASS"
      DB_BYTES=$(stat -c '%s' "$TMP/database.sql" 2>/dev/null || printf 0)
    else
      DB_STATUS="FAIL"; DB_CLASS=$(classify_db "$TMP/db.err"); BLOCKER="database_dump"
    fi
  fi
fi

# C. Nginx config copy.
if [ "$TAR_STATUS" = PASS ] && [ "$DB_STATUS" = PASS ]; then
  if [ -r /etc/nginx/sites-enabled/site.conf ] && cp /etc/nginx/sites-enabled/site.conf "$TMP/nginx_site.conf" && [ -s "$TMP/nginx_site.conf" ]; then
    NGINX_STATUS="PASS"
  else
    NGINX_STATUS="FAIL"; BLOCKER="nginx_config_copy"
  fi
fi

# D. Checksum verification over diagnostic artifacts.
if [ "$TAR_STATUS" = PASS ] && [ "$DB_STATUS" = PASS ] && [ "$NGINX_STATUS" = PASS ]; then
  ( cd "$TMP" && sha256sum website_files.tar.gz database.sql nginx_site.conf > checksums.sha256 )
  if ( cd "$TMP" && sha256sum -c checksums.sha256 >/dev/null 2>&1 ); then
    CHECKSUM_STATUS="PASS"
  else
    CHECKSUM_STATUS="FAIL"; BLOCKER="checksum_verification"
  fi
fi

OVERALL="PASS"
[ "$BLOCKER" = NONE ] || OVERALL="BLOCKED"

python3 - "$RESULT_FILE" "$OVERALL" "$BLOCKER" "$TAR_STATUS" "$TAR_CLASS" "$TAR_BYTES" "$DB_STATUS" "$DB_CLASS" "$DB_BYTES" "$NGINX_STATUS" "$CHECKSUM_STATUS" "$FRAME_LOCK" "$CACHE_FACTORY" "$HOME_HTTP" "$ARTICLE_HTTP" "$CATEGORY_HTTP" <<'PY'
import json,sys
(out,overall,blocker,tar_status,tar_class,tar_bytes,db_status,db_class,db_bytes,nginx_status,checksum_status,frame,cache_factory,home,article,category)=sys.argv[1:]
payload={
  'task':'diagnose_backup_stage',
  'diagnosis_status':overall,
  'blocking_component':blocker,
  'website_tar':tar_status,
  'website_tar_error_class':tar_class,
  'website_tar_bytes':int(tar_bytes),
  'database_dump':db_status,
  'database_error_class':db_class,
  'database_dump_bytes':int(db_bytes),
  'nginx_config_copy':nginx_status,
  'checksum_verification':checksum_status,
  'production_frame_lock':frame,
  'production_cache_factory':cache_factory,
  'production_home_http':int(home),
  'production_article91_http':int(article),
  'production_category7_http':int(category),
  'diagnostic_artifacts_removed_on_exit':True,
  'secrets_disclosed':False,
}
with open(out,'w',encoding='utf-8') as f:
    json.dump(payload,f,ensure_ascii=False,indent=2,sort_keys=True); f.write('\n')
PY

echo "BACKUP_STAGE_DIAGNOSIS=$OVERALL blocker=$BLOCKER"
