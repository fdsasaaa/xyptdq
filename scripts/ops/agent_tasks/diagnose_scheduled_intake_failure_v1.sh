#!/bin/bash
# Read-only diagnosis for a failed scheduled automatic Draft intake run.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
INTAKE_ROOT="${XYPTDQ_INTAKE_ROOT:-/var/lib/xyptdq-content/intake}"
SOURCE_DIR="$INTAKE_ROOT/source/caipiaowenzhang"
LEDGER="$INTAKE_ROOT/state.json"
DRAFT_DIR="$INTAKE_ROOT/drafts"
LOG_DIR="${XYPTDQ_INTAKE_LOG_DIR:-/var/log/xyptdq-intake}"
CRON_FILE="${XYPTDQ_INTAKE_CRON_FILE:-/etc/cron.d/xyptdq-intake}"
[ -n "$RESULT_FILE" ] || exit 2

TMP=$(mktemp -d /tmp/xyptdq-intake-failure-diagnose.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

[ -d "$REPO/.git" ] || exit 3
[ -d "$SOURCE_DIR/.git" ] || exit 4
[ -s "$LEDGER" ] || exit 5
[ -d "$DRAFT_DIR" ] || exit 6
[ -d "$LOG_DIR" ] || exit 7

python3 "$REPO/scripts/content/inventory_diff.py" \
  --source-repo="$SOURCE_DIR" \
  --website-repo="$REPO" \
  --ledger="$LEDGER" \
  --output="$TMP/inventory.json" >/dev/null 2>&1

python3 - "$LOG_DIR" "$LEDGER" "$DRAFT_DIR" "$CRON_FILE" "$TMP/inventory.json" "$RESULT_FILE" <<'PY'
import json, pathlib, re, sys, hashlib

log_dir=pathlib.Path(sys.argv[1])
ledger_path=pathlib.Path(sys.argv[2])
draft_dir=pathlib.Path(sys.argv[3])
cron_file=pathlib.Path(sys.argv[4])
inventory_path=pathlib.Path(sys.argv[5])
out=pathlib.Path(sys.argv[6])

def redact(s):
    s=re.sub(r'(?i)(password|passwd|token|secret|private[_-]?key|authorization|api[_-]?key)\s*([=:])\s*\S+', r'\1\2[REDACTED]', s)
    s=re.sub(r'https?://([^/\s:@]+):([^/\s@]+)@', r'https://\1:[REDACTED]@', s)
    s=re.sub(r'-----BEGIN [^-]*PRIVATE KEY-----.*?-----END [^-]*PRIVATE KEY-----', '[REDACTED PRIVATE KEY]', s, flags=re.S)
    return s[:2000]

rx=re.compile(r'^run_(\d{8}T\d{6}Z)\.log$')
logs=[]
for p in sorted(log_dir.glob('run_*.log')):
    m=rx.match(p.name)
    if not m or m.group(1) < '20260816T022300Z':
        continue
    raw=p.read_text(encoding='utf-8', errors='replace')
    row={'file':p.name,'bytes':len(raw.encode('utf-8')),'sha256':hashlib.sha256(raw.encode('utf-8')).hexdigest()}
    try:
        x=json.loads(raw)
        row.update({
            'parse':'json',
            'status':x.get('status'),
            'mode':x.get('mode'),
            'selected_count':len(x.get('selected_revision_ids') or []),
            'selected_revision_ids':x.get('selected_revision_ids') or [],
            'ledger_before':x.get('ledger_known_before'),
            'ledger_after':x.get('ledger_known_after'),
            'candidates_before':x.get('candidate_count_before'),
            'candidates_after':x.get('candidate_count_after'),
            'idempotent_reconciliation':x.get('idempotent_reconciliation'),
            'draft_only':x.get('draft_only'),
            'publish_at_created':x.get('publish_at_created'),
            'publisher_invoked':x.get('publisher_invoked'),
        })
    except Exception:
        row.update({'parse':'text','safe_excerpt':redact(raw)})
    logs.append(row)

ledger=json.loads(ledger_path.read_text(encoding='utf-8'))
records=ledger.get('records') or {}
inventory=json.loads(inventory_path.read_text(encoding='utf-8'))
draft_files=sorted(draft_dir.glob('*.json'))
final5={
 'LCM-CREATOR-cf50-20260813-020','LCM-CREATOR-cf50-20260813-029',
 'LCM-CREATOR-cf50-20260813-038','LCM-CREATOR-cf50-20260813-039','LCM-CREATOR-cf50-20260813-040'
}
ledger_frozen=sorted({str(r.get('article_id') or '') for r in records.values() if isinstance(r,dict)} & final5)
draft_frozen=[]
unsafe_drafts=[]
for p in draft_files:
    try:
        d=json.loads(p.read_text(encoding='utf-8'))
    except Exception:
        unsafe_drafts.append(p.name+':invalid_json')
        continue
    aid=str(d.get('source_article_id') or '')
    if aid in final5: draft_frozen.append(aid)
    if d.get('publication_state')!='draft' or 'publish_at' in d:
        unsafe_drafts.append(p.name)

cron_count=0
if cron_file.is_file():
    for line in cron_file.read_text(encoding='utf-8',errors='replace').splitlines():
        if line.lstrip().startswith('#'): continue
        if 'run_incremental_inventory_intake.sh' in line: cron_count += 1

payload={
 'task':'diagnose_scheduled_intake_failure_v1',
 'status':'PASS',
 'phase':'diagnosis_complete',
 'read_only':True,
 'detail':'captured scheduled intake log classifications and current durable reconciliation state without mutation',
 'scheduled_logs':logs,
 'scheduled_log_count':len(logs),
 'ledger_records_current':len(records),
 'runtime_draft_files_current':len(draft_files),
 'inventory_status':inventory.get('status'),
 'A_upstream_official_ready_current':inventory.get('A_upstream_official_ready'),
 'website_ingress_known_current':inventory.get('website_ingress_known'),
 'ledger_known_current':inventory.get('ledger_known'),
 'new_draft_candidates_current':inventory.get('new_draft_candidates'),
 'candidate_revision_ids_current':inventory.get('candidate_revision_ids') or [],
 'cf50_final5_release_authorized':inventory.get('cf50_final5_release_authorized'),
 'ledger_frozen_final5':ledger_frozen,
 'draft_frozen_final5':sorted(set(draft_frozen)),
 'unsafe_drafts':unsafe_drafts,
 'intake_cron_file_present':cron_file.is_file(),
 'intake_cron_active_line_count':cron_count,
 'runtime_mutation_attempted':False,
 'cms_write_attempted':False,
 'scheduled_queue_mutated':False,
 'publisher_invoked':False,
 'publisher_cron_mutated':False,
 'intake_cron_mutated':False,
 'publication_queue_consumed':False,
}
out.write_text(json.dumps(payload,ensure_ascii=False,indent=2,sort_keys=True)+'\n',encoding='utf-8')
PY
echo SCHEDULED_INTAKE_FAILURE_DIAGNOSIS=PASS
