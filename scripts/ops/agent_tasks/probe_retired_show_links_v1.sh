#!/bin/bash
# Read-only probe for retired category id=7 links on representative show pages.
set -euo pipefail
umask 077
RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
CANONICAL="https://www.laocaimi.org"
MOBILE_UA='Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 Chrome/134 Mobile Safari/537.36'
[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3
[ -d "$WEBROOT" ] || exit 4
TMP="$(mktemp -d /tmp/xyptdq-retired-links.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

cd "$REPO"
git fetch --prune origin main >/dev/null 2>&1

pc74=$(curl -skL --max-time 25 -o "$TMP/pc74.html" -w '%{http_code}' "$CANONICAL/index.php?c=show&id=74" || true)
mo74=$(curl -skL --max-time 25 -A "$MOBILE_UA" -o "$TMP/mo74.html" -w '%{http_code}' "$CANONICAL/index.php?c=show&id=74" || true)
[ "$pc74" = 200 ] && [ "$mo74" = 200 ] || exit 5

git show origin/main:site/template/pc/default/home/show.html > "$TMP/main-pc-show.html"
git show origin/main:site/template/mobile/default/home/show.html > "$TMP/main-mobile-show.html"

python3 - "$RESULT_FILE" "$pc74" "$mo74" "$TMP/pc74.html" "$TMP/mo74.html" "$WEBROOT/template/pc/default/home/show.html" "$WEBROOT/template/mobile/default/home/show.html" "$TMP/main-pc-show.html" "$TMP/main-mobile-show.html" <<'PY'
import html,json,re,sys
(out,pc_code,mo_code,pc_page,mo_page,prod_pc,prod_mo,main_pc,main_mo)=sys.argv[1:]
retired_re=re.compile(r'(?:^|[?&])c=category(?:&|&amp;).*?(?:^|[?&])id=7(?:&|$)',re.I)

def read(path):
    try:
        return open(path,encoding='utf-8',errors='ignore').read()
    except OSError:
        return ''

def anchors(path):
    s=read(path)
    rows=[]
    for m in re.finditer(r'<a\b([^>]*)>(.*?)</a\s*>',s,re.I|re.S):
        attrs=m.group(1)
        hm=re.search(r'\bhref\s*=\s*(["\'])(.*?)\1',attrs,re.I|re.S)
        if not hm:
            continue
        href=html.unescape(hm.group(2).strip())
        parsed=href.replace('&amp;','&')
        if 'c=category' in parsed and re.search(r'(?:[?&])id=7(?:&|$)',parsed):
            text=html.unescape(re.sub(r'<[^>]+>',' ',m.group(2)))
            text=re.sub(r'\s+',' ',text).strip()[:120]
            rows.append({'href':href[:300],'anchor_text':text})
    return rows

def guide_href(path):
    s=read(path)
    for m in re.finditer(r'<a\b([^>]*)>(.*?)</a\s*>',s,re.I|re.S):
        text=html.unescape(re.sub(r'<[^>]+>',' ',m.group(2)))
        text=re.sub(r'\s+',' ',text).strip()
        if '数据研究与风险说明文章' not in text:
            continue
        hm=re.search(r'\bhref\s*=\s*(["\'])(.*?)\1',m.group(1),re.I|re.S)
        return html.unescape(hm.group(2).strip()) if hm else ''
    return ''

def literal_count(path):
    return read(path).count('/index.php?c=category&id=7')

payload={
 'task':'probe_retired_show_links_v1',
 'status':'PASS',
 'pc74_http':int(pc_code),
 'mobile74_http':int(mo_code),
 'pc74_retired_links':anchors(pc_page),
 'mobile74_retired_links':anchors(mo_page),
 'pc74_guide_href':guide_href(pc_page),
 'mobile74_guide_href':guide_href(mo_page),
 'production_pc_template_literal_id7_count':literal_count(prod_pc),
 'production_mobile_template_literal_id7_count':literal_count(prod_mo),
 'main_pc_template_literal_id7_count':literal_count(main_pc),
 'main_mobile_template_literal_id7_count':literal_count(main_mo),
 'database_changed':False,
 'article_publishing_attempted':False,
 'publisher_cron_changed':False,
 'publisher_queue_consumed':False,
 'raw_page_body_published':False,
 'secrets_disclosed':False
}
with open(out,'w',encoding='utf-8') as f:
    json.dump(payload,f,ensure_ascii=False,indent=2,sort_keys=True); f.write('\n')
PY

echo "PROBE_RETIRED_SHOW_LINKS_V1=PASS"
