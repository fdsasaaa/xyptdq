#!/bin/bash
# Read-only verification of CF50 seed 021 after normal recurring Publisher cron.
set -euo pipefail
umask 077
RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
ROOT="/var/lib/xyptdq-content/CF50-20260813-wave1"
SCHEDULED="$ROOT/scheduled/LCM-CREATOR-cf50-20260813-021.json"
STATE="/var/lib/xyptdq-publisher/CF50-20260813-wave1/state.json"
BASE="/var/lib/xyptdq-publisher/CF50-20260813-wave1"
CRON="/etc/cron.d/xyptdq-publisher"
LEGACY="$REPO/content/scheduled"
SITEMAP="https://www.laocaimi.org/sitemap.xml"
EXPECTED_ID="LCM-CREATOR-cf50-20260813-021"
EXPECTED_REV="${EXPECTED_ID}:public-r1"
[ -n "$RESULT_FILE" ] || exit 2
[ -f "$SCHEDULED" ] || exit 3
[ -f "$STATE" ] || exit 4

TMP=$(mktemp -d /tmp/xyptdq-021-probe.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

python3 - "$SCHEDULED" "$STATE" "$TMP/meta.json" <<'PY'
import json,sys
s=json.load(open(sys.argv[1],encoding='utf-8'))
st=json.load(open(sys.argv[2],encoding='utf-8'))
key=str(s.get('article_key',''))
e=(st.get('articles') or {}).get(key,{})
out={
 'article_id':s.get('source_article_id') or s.get('article_id'),
 'article_key':key,
 'source_revision_id':s.get('source_revision_id'),
 'slug':s.get('slug'),
 'primary_keyword':s.get('primary_keyword'),
 'primary_seo_cluster_id':s.get('primary_seo_cluster_id'),
 'publish_at':s.get('publish_at'),
 'title_expected':s.get('title'),
 'description_expected':s.get('description') or s.get('seo_description') or '',
 'state_status':e.get('status'),
 'cms_id':e.get('cms_id'),
 'published_at':e.get('published_at'),
 'retry_count':e.get('retry_count'),
 'last_error':e.get('last_error'),
 'state_updated_at':st.get('updated_at'),
}
json.dump(out,open(sys.argv[3],'w',encoding='utf-8'),ensure_ascii=False,indent=2)
PY

CMS_ID=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("cms_id") or "")' "$TMP/meta.json")
KEY=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("article_key") or "")' "$TMP/meta.json")
URL=""; HTTP=0; CANONICAL=""; TITLE=""; H1=""; DESC=""; NOINDEX=false; SITEMAP_MEMBER=false
RECEIPT_EXISTS=false; VERIFY_EXISTS=false; VERIFY_STATUS=""

if [ -n "$CMS_ID" ] && [ "$CMS_ID" != "None" ]; then
  URL="https://www.laocaimi.org/index.php?c=show&id=$CMS_ID"
  HTTP=$(curl -skL --max-time 25 -o "$TMP/page" -w '%{http_code}' "$URL" || true)
  curl -skL --max-time 25 -o "$TMP/sitemap" "$SITEMAP" || true
  python3 - "$TMP/page" "$TMP/web.json" <<'PY'
import html,re,sys,json,pathlib
p=pathlib.Path(sys.argv[1]); s=p.read_text(encoding='utf-8',errors='ignore') if p.exists() else ''
def attr(tag,n):
    m=re.search(r'\b'+re.escape(n)+r'\s*=\s*["\']([^"\']*)["\']',tag,re.I|re.S)
    return html.unescape(m.group(1).strip()) if m else ''
def text(tag):
    m=re.search(r'<'+tag+r'\b[^>]*>(.*?)</'+tag+r'\s*>',s,re.I|re.S)
    return re.sub(r'\s+',' ',html.unescape(re.sub(r'<[^>]+>',' ',m.group(1)))).strip() if m else ''
can=''; desc=''; robots=[]
for t in re.findall(r'<link\b[^>]*>',s,re.I|re.S):
    if 'canonical' in attr(t,'rel').lower().split():
        can=attr(t,'href'); break
for t in re.findall(r'<meta\b[^>]*>',s,re.I|re.S):
    name=attr(t,'name').lower()
    if name=='description' and not desc: desc=attr(t,'content')
    if name=='robots': robots.append(attr(t,'content').lower())
json.dump({'title':text('title'),'h1':text('h1'),'canonical':can,'description':desc,
           'noindex':any('noindex' in x for x in robots)},
          open(sys.argv[2],'w',encoding='utf-8'),ensure_ascii=False)
PY
  if [ -f "$TMP/web.json" ]; then
    TITLE=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("title",""))' "$TMP/web.json")
    H1=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("h1",""))' "$TMP/web.json")
    CANONICAL=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("canonical",""))' "$TMP/web.json")
    DESC=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("description",""))' "$TMP/web.json")
    NOINDEX=$(python3 -c 'import json,sys; print(str(json.load(open(sys.argv[1])).get("noindex",False)).lower())' "$TMP/web.json")
  fi
  [ -f "$TMP/sitemap" ] && grep -Fq "$URL" "$TMP/sitemap" && SITEMAP_MEMBER=true || true
  RECEIPT=$(find "$BASE/receipts" -maxdepth 1 -type f -name "${KEY}.${CMS_ID}.json" 2>/dev/null | head -n1 || true)
  VERIFY=$(find "$BASE/seo-verification" -maxdepth 1 -type f -name "${KEY}.${CMS_ID}.json" 2>/dev/null | head -n1 || true)
  [ -n "$RECEIPT" ] && RECEIPT_EXISTS=true
  if [ -n "$VERIFY" ]; then
    VERIFY_EXISTS=true
    VERIFY_STATUS=$(python3 - "$VERIFY" <<'PY'
import json,sys
try:
    x=json.load(open(sys.argv[1],encoding='utf-8'))
    print(x.get('status') or x.get('result') or '')
except Exception:
    print('UNPARSEABLE')
PY
)
  fi
fi

CRON_COUNT=0
[ -f "$CRON" ] && CRON_COUNT=$((CRON_COUNT+1))
U=$( (crontab -l 2>/dev/null || true) | grep -c 'run_scheduled_publish.sh' || true )
CRON_COUNT=$((CRON_COUNT+U))
LEGACY_COUNT=$(find "$LEGACY" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
SCHEDULED_COUNT=$(find "$ROOT/scheduled" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' ')

python3 - "$RESULT_FILE" "$TMP/meta.json" "$URL" "$HTTP" "$TITLE" "$H1" "$CANONICAL" "$DESC" \
 "$NOINDEX" "$SITEMAP_MEMBER" "$RECEIPT_EXISTS" "$VERIFY_EXISTS" "$VERIFY_STATUS" \
 "$CRON_COUNT" "$LEGACY_COUNT" "$SCHEDULED_COUNT" "$EXPECTED_ID" "$EXPECTED_REV" <<'PY'
import json,sys
(out,meta,url,http,title,h1,canonical,desc,noindex,sm,rex,vex,vs,cron,legacy,scheduled,expected_id,expected_rev)=sys.argv[1:]
x=json.load(open(meta,encoding='utf-8'))
x.update({
 'task':'probe_cf50_021_live_v1','read_only':True,'url':url,'http_status':int(http),
 'live_title':title,'live_h1':h1,'live_canonical':canonical,'live_description':desc,
 'noindex':noindex=='true','sitemap_member':sm=='true','receipt_exists':rex=='true',
 'seo_verification_exists':vex=='true','seo_verification_status':vs,
 'publisher_cron_count':int(cron),'legacy_repository_scheduled_count':int(legacy),
 'isolated_scheduled_count':int(scheduled),'cms_write_attempted':False,
 'runtime_mutated':False,'cron_mutated':False
})
checks=[
 x.get('article_id')==expected_id,
 x.get('source_revision_id')==expected_rev,
 x.get('primary_seo_cluster_id')=='ffc_research',
 x.get('state_status')=='published',
 isinstance(x.get('cms_id'),int) and x.get('cms_id')>0,
 x.get('http_status')==200,
 x.get('live_canonical')==x.get('url'),
 not x.get('noindex'),
 bool(x.get('live_title')) and bool(x.get('live_h1')) and bool(x.get('live_description')),
 x.get('sitemap_member') is True,
 x.get('receipt_exists') is True,
 x.get('seo_verification_exists') is True,
 x.get('publisher_cron_count')==1,
 x.get('legacy_repository_scheduled_count')==11,
]
x['all_required_checks_pass']=all(checks)
x['status']='PASS' if all(checks) else 'OBSERVED'
json.dump(x,open(out,'w',encoding='utf-8'),ensure_ascii=False,indent=2,sort_keys=True)
open(out,'a').write('\n')
PY

echo PROBE_CF50_021_LIVE_V1=PASS
