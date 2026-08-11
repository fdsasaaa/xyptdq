#!/bin/bash
# Read-only classification of the prior V4 deploy log using only known marker
# presence. Never emits raw log lines, file names from tar, DB names, or errors.
set -euo pipefail
umask 077
RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
LOG="/var/log/xyptdq-agent/deploy-seo-template-phase1-v4-20260811-01.log"
[ -n "$RESULT_FILE" ] || exit 2

LOG_EXISTS="NO"; BACKUP_SUBSTAGE="UNKNOWN"; BACKUP_COMPLETE="NO"; BACKUP_VERIFY="NO"
SITE_TAR_STARTED="NO"; SITE_TAR_OK="NO"; DB_STARTED="NO"; DB_OK="NO"; NGINX_STARTED="NO"; NGINX_OK="NO"; CHECKSUM_STARTED="NO"; DEPLOY_RSYNC_STARTED="NO"
ERROR_CLASS="UNKNOWN"

if [ -s "$LOG" ]; then
  LOG_EXISTS="YES"
  grep -Fq -- '--- Website files ---' "$LOG" && SITE_TAR_STARTED="YES" || true
  # backup.sh prints a plain OK after each component; infer success from the next marker.
  grep -Fq -- '--- Database ---' "$LOG" && { DB_STARTED="YES"; SITE_TAR_OK="YES"; BACKUP_SUBSTAGE="database"; } || true
  grep -Fq -- '--- Nginx config ---' "$LOG" && { NGINX_STARTED="YES"; DB_OK="YES"; BACKUP_SUBSTAGE="nginx_config"; } || true
  grep -Fq -- '--- Checksums ---' "$LOG" && { CHECKSUM_STARTED="YES"; NGINX_OK="YES"; BACKUP_SUBSTAGE="checksums"; } || true
  grep -Fq -- '=== Backup complete ===' "$LOG" && { BACKUP_COMPLETE="YES"; BACKUP_SUBSTAGE="complete"; } || true
  grep -Fq -- 'BACKUP_VERIFY: PASS' "$LOG" && BACKUP_VERIFY="YES" || true
  grep -Fq -- '--- Sync exact-ref site code ---' "$LOG" && DEPLOY_RSYNC_STARTED="YES" || true

  if [ "$SITE_TAR_STARTED" = YES ] && [ "$SITE_TAR_OK" = NO ]; then ERROR_CLASS="website_tar_failed"
  elif [ "$DB_STARTED" = YES ] && [ "$DB_OK" = NO ]; then ERROR_CLASS="database_dump_failed"
  elif [ "$NGINX_STARTED" = YES ] && [ "$NGINX_OK" = NO ]; then ERROR_CLASS="nginx_config_copy_failed"
  elif [ "$CHECKSUM_STARTED" = YES ] && [ "$BACKUP_COMPLETE" = NO ]; then ERROR_CLASS="checksum_or_manifest_failed"
  elif [ "$BACKUP_COMPLETE" = YES ] && [ "$BACKUP_VERIFY" = NO ]; then ERROR_CLASS="post_backup_checksum_verify_failed"
  elif [ "$BACKUP_VERIFY" = YES ] && [ "$DEPLOY_RSYNC_STARTED" = YES ]; then ERROR_CLASS="failure_after_backup"
  elif grep -Fq 'backup directory already exists' "$LOG"; then ERROR_CLASS="backup_directory_collision"
  elif grep -Fq 'invalid XYPTDQ_BACKUP_ID' "$LOG"; then ERROR_CLASS="invalid_backup_id"
  elif grep -Fq 'webroot not found' "$LOG"; then ERROR_CLASS="backup_webroot_missing"
  elif grep -Fq 'CMS database config not found' "$LOG"; then ERROR_CLASS="backup_db_config_missing"
  else ERROR_CLASS="unclassified_before_or_inside_backup"
  fi
fi

python3 - "$RESULT_FILE" "$LOG_EXISTS" "$BACKUP_SUBSTAGE" "$BACKUP_COMPLETE" "$BACKUP_VERIFY" "$SITE_TAR_STARTED" "$SITE_TAR_OK" "$DB_STARTED" "$DB_OK" "$NGINX_STARTED" "$NGINX_OK" "$CHECKSUM_STARTED" "$DEPLOY_RSYNC_STARTED" "$ERROR_CLASS" <<'PY'
import json,sys
(out,log_exists,substage,complete,verify,tar_started,tar_ok,db_started,db_ok,nginx_started,nginx_ok,checksums,rsync_started,error_class)=sys.argv[1:]
payload={
 'task':'classify_seo_v4_backup_failure',
 'classification_status':'PASS',
 'blocking_item':'NONE',
 'source_log_exists':log_exists,
 'backup_substage':substage,
 'backup_complete_marker':complete,
 'backup_verify_marker':verify,
 'website_tar_started':tar_started,
 'website_tar_inferred_ok':tar_ok,
 'database_started':db_started,
 'database_inferred_ok':db_ok,
 'nginx_started':nginx_started,
 'nginx_inferred_ok':nginx_ok,
 'checksums_started':checksums,
 'deploy_rsync_started':rsync_started,
 'error_class':error_class,
 'raw_log_published':False,
 'secrets_disclosed':False,
}
with open(out,'w',encoding='utf-8') as f:
 json.dump(payload,f,ensure_ascii=False,indent=2,sort_keys=True); f.write('\n')
PY

echo "SEO_V4_BACKUP_CLASSIFICATION=PASS class=$ERROR_CLASS substage=$BACKUP_SUBSTAGE"
