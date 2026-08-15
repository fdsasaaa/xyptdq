#!/bin/bash
# Resilient read-only diagnostic for CF50-021 Sitemap/canonical mismatch.
set -uo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
GENERATOR="$REPO/scripts/seo/generate_sitemap.php"
LIVE_SITEMAP="https://www.laocaimi.org/sitemap.xml"
PAGE="https://www.laocaimi.org/index.php?c=show&id=94"
EXPECTED="$PAGE"
SLUG="ffc-five-direct-distinct4"
BASE="/var/lib/xyptdq-publisher/CF50-20260813-wave1"

[ -n "$RESULT_FILE" ] || exit 2
TMP=$(mktemp -d /tmp/xyptdq-021-sitemap-v2.XXXXXX) || exit 3
trap 'rm -rf "$TMP"' EXIT

GEN_RC=99
GEN_OUT=""
if [ -s "$GENERATOR" ]; then
  GEN_OUT=$(XYPTDQ_WEBROOT="$WEBROOT" XYPTDQ_SITEMAP="$TMP/generated.xml" php "$GENERATOR" 2>&1)
  GEN_RC=$?
fi
curl -skL --max-time 25 -o "$TMP/live.xml" "$LIVE_SITEMAP" >/dev/null 2>&1 || true
curl -skL --max-time 25 -o "$TMP/page.html" "$PAGE" >/dev/null 2>&1 || true
VERIFY=$(find "$BASE/seo-verification" -maxdepth 1 -type f -name "*.94.json" 2>/dev/null | head -n1 || true)
LOG=$(find /var/log/xyptdq-publisher -maxdepth 1 -type f -name 'run_*.log' 2>/dev/null | sort | tail -n1 || true)

python3 - "$RESULT_FILE" "$TMP/generated.xml" "$TMP/live.xml" "$TMP/page.html" "$EXPECTED" "$SLUG" "$GEN_RC" "$GEN_OUT" "$VERIFY" "$LOG" <<'PY'
import html, json, pathlib, re, sys
(out, generated_p, live_p, page_p, expected, slug, gen_rc, gen_out, verify_p, log_p)=sys.argv[1:]

def read(path):
    try:
        return pathlib.Path(path).read_text(encoding='utf-8', errors='ignore')
    except Exception:
        return ''

def locs(xml):
    return [html.unescape(x.strip()) for x in re.findall(r'<loc>(.*?)</loc>', xml, re.I|re.S)]

def canonical(page):
    for tag in re.findall(r'<link\b[^>]*>', page, re.I|re.S):
        rel=re.search(r'''\brel\s*=\s*["']([^"']*)["']''', tag, re.I|re.S)
        if rel and 'canonical' in rel.group(1).lower().split():
            href=re.search(r'''\bhref\s*=\s*["']([^"']*)["']''', tag, re.I|re.S)
            if href:
                return html.unescape(href.group(1).strip())
    return ''

def relevant(urls):
    rows=[]
    for u in urls:
        if u == expected or slug in u or 'id=94' in u:
            if u not in rows:
                rows.append(u)
    return rows[:20]

generated=locs(read(generated_p))
live=locs(read(live_p))
page=read(page_p)
verify_raw=read(verify_p) if verify_p else ''
verify=None
if verify_raw:
    try: verify=json.loads(verify_raw)
    except Exception: verify={'unparseable': True, 'raw_excerpt': verify_raw[:1000]}
log_lines=[]
if log_p:
    for line in read(log_p).splitlines():
        if '94' in line or 'sitemap' in line.lower() or 'seo_verify' in line.lower():
            log_lines.append(line[:1000])
result={
    'task':'diagnose_cf50_021_sitemap_url_v2',
    'status':'PASS',
    'read_only':True,
    'cms_write_attempted':False,
    'cron_mutated':False,
    'queue_consumed':False,
    'cms_id':94,
    'expected_canonical_url':expected,
    'live_page_canonical':canonical(page),
    'generator_exit_code':int(gen_rc),
    'generator_output':gen_out[-2000:],
    'generated_sitemap_exists':pathlib.Path(generated_p).is_file(),
    'generated_expected_member':expected in generated,
    'live_expected_member':expected in live,
    'generated_relevant_locs':relevant(generated),
    'live_relevant_locs':relevant(live),
    'generated_url_count':len(generated),
    'live_url_count':len(live),
    'verification_file':pathlib.Path(verify_p).name if verify_p else '',
    'verification_json':verify,
    'latest_publisher_log':pathlib.Path(log_p).name if log_p else '',
    'publisher_log_relevant_excerpt':log_lines[-30:],
}
if int(gen_rc) != 0:
    cause='sitemap_generator_failed'
elif expected not in generated and any(slug in u for u in generated):
    cause='managed_article_stored_relative_url_selected_instead_of_show_canonical'
elif expected in generated and expected not in live:
    cause='production_sitemap_stale_or_not_regenerated_from_current_generator'
elif expected not in generated:
    cause='generated_sitemap_omits_managed_article'
else:
    cause='no_current_sitemap_membership_gap_detected'
result['root_cause_candidate']=cause
with open(out,'w',encoding='utf-8') as fh:
    json.dump(result,fh,ensure_ascii=False,indent=2,sort_keys=True)
    fh.write('\n')
PY

echo DIAGNOSE_CF50_021_SITEMAP_URL_V2=PASS
exit 0
