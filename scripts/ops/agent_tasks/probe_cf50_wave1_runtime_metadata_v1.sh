#!/bin/bash
# Read-only probe for CF50 wave1 Draft/Scheduled metadata. Never outputs article body.
set -euo pipefail
umask 077
RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
ROOT="/var/lib/xyptdq-content/CF50-20260813-wave1"
DRAFT_DIR="$ROOT/drafts"
SCHEDULED_DIR="$ROOT/scheduled"
CRON_FILE="/etc/cron.d/xyptdq-publisher"
[ -n "$RESULT_FILE" ] || exit 2
[ -d "$DRAFT_DIR" ] || exit 3
[ -d "$SCHEDULED_DIR" ] || exit 4
TMP=$(mktemp); trap 'rm -f "$TMP"' EXIT
python3 - "$DRAFT_DIR" "$SCHEDULED_DIR" "$TMP" <<'PY'
import json,pathlib,sys
expected=[("LCM-CREATOR-cf50-20260813-011","2026-08-14T19:00:00+08:00"),("LCM-CREATOR-cf50-20260813-021","2026-08-15T10:00:00+08:00"),("LCM-CREATOR-cf50-20260813-031","2026-08-15T19:00:00+08:00"),("LCM-CREATOR-cf50-20260813-041","2026-08-16T10:00:00+08:00"),("LCM-CREATOR-cf50-20260813-046","2026-08-16T19:00:00+08:00"),("LCM-CREATOR-cf50-20260813-002","2026-08-17T10:00:00+08:00"),("LCM-CREATOR-cf50-20260813-012","2026-08-17T19:00:00+08:00"),("LCM-CREATOR-cf50-20260813-022","2026-08-18T10:00:00+08:00"),("LCM-CREATOR-cf50-20260813-032","2026-08-18T19:00:00+08:00"),("LCM-CREATOR-cf50-20260813-037","2026-08-19T10:00:00+08:00"),("LCM-CREATOR-cf50-20260813-049","2026-08-19T19:00:00+08:00")]
dr,sr,out=map(pathlib.Path,sys.argv[1:4]); rows=[]
for aid,when in expected:
 row={'article_id':aid,'expected_publish_at':when,'draft_exists':False,'scheduled_exists':False,'mismatches':[]}
 dp=dr/f'{aid}.json'; sp=sr/f'{aid}.json'
 if dp.is_file():
  d=json.loads(dp.read_text(encoding='utf-8')); row['draft_exists']=True
  row['draft']={k:d.get(k) for k in ('article_id','publication_state','site_category_key','catid','primary_seo_cluster_id','source_revision_id','source_intake_mode','source_batch_id','source_creator_batch_id')}
  row['draft']['has_publish_at']='publish_at' in d
 else: d={}; row['mismatches'].append('draft_missing')
 if sp.is_file():
  s=json.loads(sp.read_text(encoding='utf-8')); row['scheduled_exists']=True
  row['scheduled']={k:s.get(k) for k in ('article_id','publication_state','publish_at','site_category_key','catid','primary_seo_cluster_id','source_revision_id','source_intake_mode','source_batch_id','source_creator_batch_id')}
 else: s={}; row['mismatches'].append('scheduled_missing')
 if d:
  if d.get('article_id')!=aid: row['mismatches'].append('draft_article_id')
  if d.get('publication_state')!='draft': row['mismatches'].append('draft_state')
  if 'publish_at' in d: row['mismatches'].append('draft_has_publish_at')
  if d.get('site_category_key')!='tzjq' or int(d.get('catid',0))!=3: row['mismatches'].append('draft_category')
  if d.get('primary_seo_cluster_id')!='ffc_research': row['mismatches'].append('draft_cluster')
  if d.get('source_revision_id')!=aid+':public-r1': row['mismatches'].append('draft_revision')
  if d.get('source_intake_mode')!='public_release_transfer_canary': row['mismatches'].append('draft_intake_mode')
 if s:
  if s.get('article_id')!=aid: row['mismatches'].append('scheduled_article_id')
  if s.get('publication_state')!='scheduled': row['mismatches'].append('scheduled_state')
  if s.get('publish_at')!=when: row['mismatches'].append('scheduled_publish_at')
  if s.get('site_category_key')!='tzjq' or int(s.get('catid',0))!=3: row['mismatches'].append('scheduled_category')
  if s.get('primary_seo_cluster_id')!='ffc_research': row['mismatches'].append('scheduled_cluster')
  if s.get('source_revision_id')!=aid+':public-r1': row['mismatches'].append('scheduled_revision')
  if s.get('source_intake_mode')!='public_release_transfer_canary': row['mismatches'].append('scheduled_intake_mode')
 if d and s:
  for key in ('source_content_hash','source_fingerprint','source_parent_content_hash','source_parent_fingerprint','slug','primary_keyword'):
   if d.get(key)!=s.get(key): row['mismatches'].append('draft_scheduled_'+key)
 rows.append(row)
json.dump({'status':'PASS','read_only':True,'runtime_root':'/var/lib/xyptdq-content/CF50-20260813-wave1','rows':rows,'mismatch_count':sum(len(r['mismatches']) for r in rows)},out.open('w'),ensure_ascii=False,indent=2)
PY
CRON_COUNT=0; [ -f "$CRON_FILE" ] && CRON_COUNT=$((CRON_COUNT+1)); U=$( (crontab -l 2>/dev/null || true) | grep -c 'run_scheduled_publish.sh' || true ); CRON_COUNT=$((CRON_COUNT+U))
LEGACY_COUNT=$(find "$REPO/content/scheduled" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
python3 - "$RESULT_FILE" "$TMP" "$CRON_COUNT" "$LEGACY_COUNT" <<'PY'
import json,sys
out,tmp,cron,legacy=sys.argv[1:]; x=json.load(open(tmp,encoding='utf-8')); x.update({'task':'probe_cf50_wave1_runtime_metadata_v1','publisher_cron_count':int(cron),'legacy_repository_scheduled_count':int(legacy),'cms_write_attempted':False,'runtime_mutated':False,'cron_mutated':False}); json.dump(x,open(out,'w',encoding='utf-8'),ensure_ascii=False,indent=2); open(out,'a').write('\n')
PY
echo PROBE_CF50_WAVE1_RUNTIME_METADATA_V1=PASS
