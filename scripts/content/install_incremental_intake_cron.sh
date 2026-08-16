#!/bin/bash
# Install exactly one Draft-only inventory intake cron after policy activation.
set -euo pipefail
umask 077

REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
CRON_FILE="${XYPTDQ_INTAKE_CRON_FILE:-/etc/cron.d/xyptdq-intake}"
POLICY="$REPO/config/content_inventory_policy.json"
SYNC_POLICY="$REPO/config/content_source_sync_policy.json"
RUNNER="$REPO/scripts/content/run_incremental_inventory_intake.sh"

fail() { echo "[install-intake-cron] ERROR: $*" >&2; exit 1; }

[ -s "$POLICY" ] && [ -s "$SYNC_POLICY" ] && [ -s "$RUNNER" ] || fail "required intake files missing"
ENABLED=$(python3 - "$POLICY" "$SYNC_POLICY" <<'PY'
import json,sys
a=json.load(open(sys.argv[1],encoding='utf-8')); b=json.load(open(sys.argv[2],encoding='utf-8'))
print('yes' if (a.get('activation') or {}).get('automatic_intake_enabled') is True and b.get('sync_enabled') is True else 'no')
PY
)
[ "$ENABLED" = yes ] || fail "automatic Draft intake policies are not enabled"

# Existing references outside the managed cron file are forbidden to prevent duplicate intake runs.
while IFS= read -r hit; do
  [ -z "$hit" ] && continue
  file=${hit%%:*}
  [ "$file" = "$CRON_FILE" ] || fail "unmanaged intake cron reference exists: $hit"
done < <(grep -R -n -F 'run_incremental_inventory_intake.sh' /etc/cron.d /etc/crontab 2>/dev/null || true)

TMP=$(mktemp /tmp/xyptdq-intake-cron.XXXXXX)
trap 'rm -f "$TMP"' EXIT
cat > "$TMP" <<EOF
# Managed by xyptdq. Draft-only source inventory reconciliation; never publishes content.
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
23 * * * * root XYPTDQ_INTAKE_MODE=auto XYPTDQ_INTAKE_LIMIT=25 /bin/bash $RUNNER >/dev/null 2>&1
EOF
chmod 0644 "$TMP"
chown root:root "$TMP"
install -o root -g root -m 0644 "$TMP" "$CRON_FILE"

COUNT=$(grep -R -h -F 'run_incremental_inventory_intake.sh' /etc/cron.d /etc/crontab 2>/dev/null | grep -v '^#' | wc -l | tr -d ' ')
[ "$COUNT" = 1 ] || fail "expected exactly one active intake cron, found $COUNT"
grep -Fq '23 * * * * root XYPTDQ_INTAKE_MODE=auto XYPTDQ_INTAKE_LIMIT=25 /bin/bash' "$CRON_FILE" || fail "managed intake cron line mismatch"
echo INCREMENTAL_INTAKE_CRON=PASS
