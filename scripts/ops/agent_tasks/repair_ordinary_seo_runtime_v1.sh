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
FILES=(template/pc/default/home/seo_header.html template/mobile/default/home/seo_header.html)
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
php /dev/stdin "$REPO" > "$TMP/duplicate-proof.json" <<'PHP'
<?php
require $argv[1].'/scripts/content/cms_publish_native_adapter.php';
$c=xyptdq_native_load_db_config(); $pdo=xyptdq_native_open_pdo($c);
$prefix=xyptdq_native_identifier((string)($c['DBPrefix']??'dr_'),'prefix');
$expected=[105=>'f816fb7803174d689dea36e135c62bd10c443bc8d0ecb04fa21bf35fd117168d',106=>'d77dc156ba8b20334dacb5b835daa0894523ed6210f3295d3f4dd2ab280eccc5'];
$visible=[];$links=[];
foreach ($expected as $id=>$hash) {
    $q=$pdo->prepare('SELECT catid,content FROM `'.$prefix.'1_news_data_0` WHERE id=?');$q->execute([$id]);$r=$q->fetch();
    if (!$r) {throw new RuntimeException('duplicate source missing');} ksort($r);
    if (hash('sha256',json_encode($r,JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES))!==$hash) {throw new RuntimeException('duplicate body drifted; review required');}
    $body=(string)$r['content'];
    $visible[$id]=preg_replace('/\s+/u',' ',trim(html_entity_decode(strip_tags($body),ENT_QUOTES,'UTF-8')));
    preg_match_all('/href\s*=\s*[\x22\x27]([^\x22\x27]+)[\x22\x27]/i',$body,$matches);$links[$id]=$matches[1];
}
if ($visible[105]!==$visible[106] || $links[105]!==$links[106]) {throw new RuntimeException('duplicate content/attachment mismatch');}
echo json_encode(['visible_text_identical'=>true,'download_links_identical'=>true,'canonical_id'=>105,'redirect_id'=>106]);
PHP

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
        'future_ordinary_schedule':future,'final_ledger_reconciliation':rec}
out.write_text(json.dumps(result,ensure_ascii=False,indent=2,sort_keys=True)+'\n')
PY
trap - ERR
echo ORDINARY_SEO_RUNTIME_RECOVERY=PASS
