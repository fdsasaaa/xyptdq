#!/bin/bash
# Authorized recovery of ordinary SEO scheduling/ledger and duplicate entry 106.
# No CMS content writes; the first new item is scheduled for a future normal slot.
set -euo pipefail
umask 077
: "${XYPTDQ_AGENT_RESULT_FILE:?result file required}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
ROOT=/var/lib/xyptdq-content
PUB=/var/lib/xyptdq-publisher
CRON=/etc/cron.d/xyptdq-promotion
BACKUP="/var/backups/xyptdq/ordinary-seo-$(date -u +%Y%m%dT%H%M%SZ)-$$"
TMP=$(mktemp -d /tmp/xyptdq-ordinary-recovery.XXXXXX)
PHASE=init
DEPLOYED=0
CRON_WRITTEN=0
FILES=(index.php template/pc/default/home/seo_header.html template/mobile/default/home/seo_header.html)
cleanup(){ rm -rf "$TMP"; }
trap cleanup EXIT
failed(){
    rc=$?; trap - ERR
    if [ "$DEPLOYED" = 1 ]; then
        for f in "${FILES[@]}"; do install -o www-data -g www-data -m 0644 "$BACKUP/$f" "$WEBROOT/$f"; done
        XYPTDQ_WEBROOT="$WEBROOT" bash "$REPO/scripts/content/safe_clear_cache.sh" >/dev/null || true
    fi
    if [ "$CRON_WRITTEN" = 1 ]; then install -o root -g root -m 0644 "$BACKUP/promotion.cron" "$CRON"; fi
    python3 - "$XYPTDQ_AGENT_RESULT_FILE" "$PHASE" "$rc" "$BACKUP" <<'PY'
import json, sys
out, phase, rc, backup=sys.argv[1:]
with open(out,'w') as f:
    json.dump({'task':'repair_ordinary_seo_runtime_v1','status':'BLOCKED','phase':phase,
               'exit_code':int(rc),'backup':backup,'cms_write':False,'publisher_invoked':False,
               'note':'Template/cron installation rolled back if changed; validated ledger recovery is retained.'},f)
PY
    exit "$rc"
}
trap failed ERR
PHASE=sync
git -C "$REPO" fetch --prune origin main >/dev/null 2>&1
git -C "$REPO" merge-base --is-ancestor "$XYPTDQ_AGENT_REQUIRED_COMMIT" origin/main
git -C "$REPO" checkout -q main
git -C "$REPO" reset --hard origin/main >/dev/null
grep -Fq 'XYPTDQ_PUBLISH_SOURCE=/var/lib/xyptdq-content/ordinary-seo/scheduled' /etc/cron.d/xyptdq-publisher
grep -Fq 'XYPTDQ_PUBLISH_STATE=/var/lib/xyptdq-publisher/ordinary-seo/state.json' /etc/cron.d/xyptdq-publisher
grep -Fq 'XYPTDQ_PUBLISH_LOCK=/var/lib/xyptdq-publisher/ordinary-seo/publisher.lock' /etc/cron.d/xyptdq-publisher

PHASE=duplicate_identity_preflight
python3 - "$TMP/duplicate-proof.json" <<'PY'
import hashlib, json, pathlib, sys, urllib.request
from html.parser import HTMLParser
from urllib.parse import urljoin
class Article(HTMLParser):
    def __init__(self):
        super().__init__(); self.depth=0; self.skip=0; self.text=[]; self.links=[]
    def handle_starttag(self, tag, attrs):
        a=dict(attrs)
        if self.depth==0:
            if 'xyptdq-content' in a.get('class','').split():self.depth=1
            return
        if tag not in ('area','base','br','col','embed','hr','img','input','link','meta','param','source','track','wbr'):self.depth+=1
        if tag in ('script','style'):self.skip+=1
        if tag=='a' and a.get('href'):self.links.append(urljoin('https://www.laocaimi.org/',a['href']))
    def handle_endtag(self, tag):
        if self.depth:
            if tag in ('script','style'):self.skip-=1
            self.depth-=1
    def handle_data(self, text):
        if self.depth and not self.skip:self.text.append(text)
pages=[]
for article_id in (105,106):
    with urllib.request.urlopen('https://www.laocaimi.org/index.php?c=show&id='+str(article_id),timeout=25) as response:
        assert response.status==200
        parser=Article();parser.feed(response.read().decode('utf-8'))
    text=' '.join(' '.join(parser.text).split())
    assert len(text)>180 and parser.links==['https://www.laocaimi.org/uploadfile/202610/a698cade5a2dd96.zip']
    pages.append({'id':article_id,'visible_body_sha256':hashlib.sha256(text.encode()).hexdigest(),'download_links':parser.links})
assert pages[0]['visible_body_sha256']==pages[1]['visible_body_sha256'], 'visible article body differs'
pathlib.Path(sys.argv[1]).write_text(json.dumps({'visible_text_identical':True,'download_links_identical':True,'pages':pages}),encoding='utf-8')
PY

PHASE=backup
mkdir -p "$BACKUP"; chmod 0700 "$BACKUP"
for f in "${FILES[@]}"; do mkdir -p "$BACKUP/$(dirname "$f")"; cp -a "$WEBROOT/$f" "$BACKUP/$f"; done
cp -a "$CRON" "$BACKUP/promotion.cron"
cp -a "$WEBROOT/sitemap.xml" "$BACKUP/sitemap.xml"
flock "$ROOT/intake/intake.lock" cp -a "$ROOT/intake/state.json" "$BACKUP/intake-state.json"
cp -a "$PUB/ordinary-seo/state.json" "$BACKUP/ordinary-state.json"
sha256sum "$PUB/state.json" "$PUB/CF50-20260813-wave1/state.json" "$WEBROOT/cache/frame.lock" > "$TMP/protected.before"

PHASE=ledger_recovery
python3 "$REPO/scripts/content/reconcile_publication_ledger.py" \
  --queue="$ROOT/ordinary-seo/scheduled" --state="$PUB/ordinary-seo/state.json" \
  --receipts="$PUB/ordinary-seo/receipts" --commit > "$TMP/recovery.json"

PHASE=template_deploy
DEPLOYED=1
for f in "${FILES[@]}"; do php -l "$REPO/site/$f" >/dev/null; install -o www-data -g www-data -m 0644 "$REPO/site/$f" "$WEBROOT/$f"; done
XYPTDQ_WEBROOT="$WEBROOT" bash "$REPO/scripts/content/safe_clear_cache.sh" >/dev/null
XYPTDQ_WEBROOT="$WEBROOT" php "$REPO/scripts/seo/generate_sitemap.php" > "$TMP/sitemap-result.txt"

PHASE=live_redirect_verify
for ua in 'xyptdq-recovery/1' 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/134 Mobile Safari/537.36'; do
    code=$(curl -sS --max-time 25 -A "$ua" -D "$TMP/headers" -o /dev/null -w '%{http_code}' 'https://www.laocaimi.org/index.php?c=show&id=106')
    [ "$code" = 301 ]
    tr -d '\r' < "$TMP/headers" | grep -Fqi 'Location: https://www.laocaimi.org/index.php?c=show&id=105'
done
python3 - "$WEBROOT/sitemap.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
urls={(x.text or '').strip() for x in ET.parse(sys.argv[1]).iter() if x.tag.endswith('loc')}
assert 'https://www.laocaimi.org/index.php?c=show&id=105' in urls
assert 'https://www.laocaimi.org/index.php?c=show&id=106' not in urls
PY
php "$REPO/scripts/seo/verify_publication_seo.php" \
  --receipt="$PUB/ordinary-seo/receipts/lcm-angle-0b6f9c192c45dc31.104.json" > "$TMP/live-seo.json"

PHASE=cron_environment_smoke
# Exercise the exact unattended invocation: no bridge-only result variable.
env -u XYPTDQ_AGENT_RESULT_FILE XYPTDQ_REPO_DIR="$REPO" \
  /bin/bash "$REPO/scripts/ops/agent_tasks/promote_ordinary_seo_v1.sh" > "$TMP/promotion-first.log" 2>&1
cp "$ROOT/ordinary-seo/promotion-last-run.json" "$TMP/promotion-first.json"
env -u XYPTDQ_AGENT_RESULT_FILE XYPTDQ_REPO_DIR="$REPO" \
  /bin/bash "$REPO/scripts/ops/agent_tasks/promote_ordinary_seo_v1.sh" > "$TMP/promotion-repeat.log" 2>&1
cp "$ROOT/ordinary-seo/promotion-last-run.json" "$TMP/promotion-repeat.json"

PHASE=cron_install
cat > "$TMP/promotion.cron" <<EOF
# Managed ordinary SEO inventory poll; editorial slots remain Tue/Thu/Sat 10:00 +08.
# Hourly polling avoids dependence on cron implementations' CRON_TZ support.
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
5 * * * * root XYPTDQ_AGENT_RESULT_FILE=$ROOT/ordinary-seo/promotion-last-run.json /bin/bash $REPO/scripts/ops/agent_tasks/promote_ordinary_seo_v1.sh >/dev/null 2>&1
EOF
CRON_WRITTEN=1
install -o root -g root -m 0644 "$TMP/promotion.cron" "$CRON"
python3 - <<'PY'
import pathlib,re
paths=[p for p in pathlib.Path('/etc/cron.d').iterdir() if p.is_file() and re.fullmatch(r'[A-Za-z0-9_-]+',p.name)]+[pathlib.Path('/etc/crontab')]
lines=[]
for p in paths:
    if p.is_file():lines.extend(s for s in p.read_text().splitlines() if s.strip() and not s.lstrip().startswith('#'))
assert sum('promote_ordinary_seo_v1.sh' in s for s in lines)==1
assert sum('run_scheduled_publish.sh' in s for s in lines)==1
PY

PHASE=final_verify
sha256sum -c "$TMP/protected.before" >/dev/null
python3 "$REPO/scripts/content/reconcile_publication_ledger.py" \
  --queue="$ROOT/ordinary-seo/scheduled" --state="$PUB/ordinary-seo/state.json" \
  --receipts="$PUB/ordinary-seo/receipts" > "$TMP/final-ledger.json"
python3 - "$XYPTDQ_AGENT_RESULT_FILE" "$TMP" "$BACKUP" "$ROOT" "$PUB" <<'PY'
import datetime, json, pathlib, sys
out,tmp,backup,root,pub=[pathlib.Path(x) for x in sys.argv[1:]]
def load(p):return json.loads(p.read_text())
first=load(tmp/'promotion-first.json');repeat=load(tmp/'promotion-repeat.json');rec=load(tmp/'final-ledger.json')
assert first['status']=='PASS' and repeat['status']=='PASS' and repeat['added_this_run']==0
assert rec['changed_count']==0
state=load(pub/'ordinary-seo/state.json'); ledger=load(root/'intake/state.json')
row=ledger['records']['LCM-ANGLE-0b6f9c192c45dc31:public-r1']
assert row['lifecycle_state']=='published' and row['cms_id']==104
future=[]
for p in (root/'ordinary-seo/scheduled').glob('*.json'):
    q=load(p)
    if state['articles'].get(q['article_key'],{}).get('status')!='published':
        assert q['source_batch_id'].startswith('DAILY-')
        assert datetime.datetime.fromisoformat(q['publish_at'])>datetime.datetime.now(datetime.timezone.utc)
        future.append({k:q[k] for k in ('source_article_id','source_batch_id','publish_at')})
assert len(future)<=1
result={'task':'repair_ordinary_seo_runtime_v1','status':'PASS','phase':'complete','backup':str(backup),
        'cms_write':False,'publisher_invoked':False,'cf50_and_legacy_state_unchanged':True,
        'framework_lock_unchanged':True,'canary_104_ledger_published':True,
        'canary_104_live_seo':load(tmp/'live-seo.json'),'ledger_recovery':load(tmp/'recovery.json'),
        'cron_environment_first_run':first,'cron_environment_repeat_run':repeat,
        'promotion_cron_singleton':True,'publisher_cron_singleton':True,
        'duplicate_106_redirects_to_105_pc_and_mobile':True,'sitemap_duplicate_removed':True,
        'duplicate_content_comparison':load(tmp/'duplicate-proof.json'),
        'future_ordinary_schedule':future,'final_ledger_reconciliation':rec}
out.write_text(json.dumps(result,ensure_ascii=False,indent=2,sort_keys=True)+'\n')
PY
trap - ERR
echo ORDINARY_SEO_RUNTIME_RECOVERY=PASS
