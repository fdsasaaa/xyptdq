#!/bin/bash
# Read-only production SEO re-audit after Phase 1 templates and Phase 2 homepage.
# Emits only sanitized counts/status fields through the Server Bridge.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
CANONICAL="https://www.laocaimi.org"

[ -n "$RESULT_FILE" ] || exit 2

TMP="$(mktemp -d /tmp/xyptdq-seo-reaudit.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

fetch_page() {
  local name="$1" url="$2" ua="${3:-}"
  if [ -n "$ua" ]; then
    curl -skL --max-time 30 -A "$ua" -o "$TMP/$name.html" -w '%{http_code}' "$url" > "$TMP/$name.code"
  else
    curl -skL --max-time 30 -o "$TMP/$name.html" -w '%{http_code}' "$url" > "$TMP/$name.code"
  fi
}

MOBILE_UA='Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 Chrome/134 Mobile Safari/537.36'

fetch_page home "$CANONICAL/"
fetch_page mobile_home "$CANONICAL/" "$MOBILE_UA"
fetch_page category "$CANONICAL/index.php?c=category&id=7"
fetch_page mobile_category "$CANONICAL/index.php?c=category&id=7" "$MOBILE_UA"
fetch_page article "$CANONICAL/index.php?c=show&id=91"
fetch_page mobile_article "$CANONICAL/index.php?c=show&id=91" "$MOBILE_UA"
fetch_page platform "$CANONICAL/index.php?c=show&id=19"
fetch_page mobile_platform "$CANONICAL/index.php?c=show&id=19" "$MOBILE_UA"
fetch_page robots "$CANONICAL/robots.txt"
fetch_page sitemap "$CANONICAL/sitemap.xml"

python3 - "$TMP" "$RESULT_FILE" "$CANONICAL" <<'PY'
import json, pathlib, re, sys
tmp = pathlib.Path(sys.argv[1])
out = pathlib.Path(sys.argv[2])
canonical = sys.argv[3]

pages = {
    "pc_home": ("home", True),
    "mobile_home": ("mobile_home", False),
    "pc_category": ("category", True),
    "mobile_category": ("mobile_category", True),
    "pc_article": ("article", True),
    "mobile_article": ("mobile_article", True),
    "pc_platform": ("platform", True),
    "mobile_platform": ("mobile_platform", True),
}

def code(name):
    try:
        return int((tmp / f"{name}.code").read_text().strip())
    except Exception:
        return 0

def text(name):
    try:
        return (tmp / f"{name}.html").read_text(encoding="utf-8", errors="ignore")
    except Exception:
        return ""

def count(s, pat):
    return len(re.findall(pat, s, re.I | re.S))

def meta_contents(s, name):
    tags = re.findall(r"<meta\b[^>]*>", s, re.I | re.S)
    vals = []
    for tag in tags:
        nm = re.search(r"\bname=[\"']([^\"']*)[\"']", tag, re.I)
        if not nm or nm.group(1).strip().lower() != name.lower():
            continue
        cm = re.search(r"\bcontent=[\"']([^\"']*)[\"']", tag, re.I | re.S)
        vals.append(cm.group(1).strip() if cm else "")
    return vals

def hrefs_for_rel(s, rel_name):
    vals = []
    for tag in re.findall(r"<link\b[^>]*>", s, re.I | re.S):
        rel = re.search(r"\brel=[\"']([^\"']*)[\"']", tag, re.I)
        if not rel or rel_name.lower() not in rel.group(1).lower().split():
            continue
        href = re.search(r"\bhref=[\"']([^\"']*)[\"']", tag, re.I | re.S)
        vals.append(href.group(1).strip() if href else "")
    return vals

def audit_html(label, name, require_jsonld):
    s = text(name)
    low = s.lower()
    issues = []
    http = code(name)
    if http != 200:
        issues.append("http_not_200")
        return issues
    if count(s, r"<!doctype\b") != 1:
        issues.append("doctype_not_one")
    if count(s, r"<html\b") != 1:
        issues.append("html_document_not_one")
    if count(s, r"<head\b") != 1:
        issues.append("head_not_one")
    if count(s, r"<body\b") != 1:
        issues.append("body_not_one")
    if count(s, r"<title\b") != 1:
        issues.append("title_not_one")
    desc = meta_contents(s, "description")
    if len(desc) != 1 or not desc[0]:
        issues.append("description_missing_or_duplicate")
    robots = [x.lower() for x in meta_contents(s, "robots")]
    if any(("none" in x or "noindex" in x) for x in robots):
        issues.append("robots_blocks_index")
    canon = hrefs_for_rel(s, "canonical")
    if len(canon) != 1 or not canon[0]:
        issues.append("canonical_missing_or_duplicate")
    elif not canon[0].startswith(canonical):
        issues.append("canonical_host_mismatch")
    if count(s, r"<h1\b") != 1:
        issues.append("h1_not_one")
    if require_jsonld and count(s, r'application/ld\+json') < 1:
        issues.append("jsonld_missing")
    if "站长素材" in s:
        issues.append("legacy_demo_content_present")
    if "content=\"none\"" in low or "content='none'" in low:
        issues.append("legacy_robots_none_present")
    return issues

issues_by_page = {}
for label, (name, require_jsonld) in pages.items():
    issues_by_page[label] = audit_html(label, name, require_jsonld)

home = text("home")
for marker, issue in [
    ("彩票数据研究、方案验证与平台资料导航", "home_expected_h1_copy_missing"),
    ("平台资料导航", "home_platform_section_missing"),
    ("最新研究文章", "home_article_section_missing"),
    ("seo-article-section", "home_article_marker_missing"),
    ("click_pop", "home_notice_function_missing"),
    ("ptitem", "home_platform_loop_marker_missing"),
]:
    if marker not in home:
        issues_by_page["pc_home"].append(issue)

robots_http = code("robots")
robots_text = text("robots")
robots_issues = []
if robots_http != 200:
    robots_issues.append("robots_http_not_200")
if "Sitemap: https://www.laocaimi.org/sitemap.xml" not in robots_text:
    robots_issues.append("canonical_sitemap_not_advertised")
if re.search(r"(?im)^\s*Disallow:\s*/\s*$", robots_text):
    robots_issues.append("robots_disallow_all")

sitemap_http = code("sitemap")
sitemap_text = text("sitemap")
sitemap_issues = []
if sitemap_http != 200:
    sitemap_issues.append("sitemap_http_not_200")
if canonical not in sitemap_text:
    sitemap_issues.append("sitemap_canonical_host_missing")
if "index.php?c=show&amp;id=91" not in sitemap_text and "index.php?c=show&id=91" not in sitemap_text:
    sitemap_issues.append("article91_missing_from_sitemap")

legacy_external_dependency_count = 0
for label, (name, _) in pages.items():
    s = text(name)
    hits = re.findall(r"(?:src|href)=[\"'](https?://[^\"']+)[\"']", s, re.I)
    for url in hits:
        u = url.lower()
        if any(x in u for x in ("zzsc", "jqueryui.com/demos", "bootstrapcdn.com/demo")):
            legacy_external_dependency_count += 1

counts = {k: len(v) for k,v in issues_by_page.items()}
issue_count = sum(counts.values()) + len(robots_issues) + len(sitemap_issues) + legacy_external_dependency_count

payload = {
    "task": "whole_site_seo_reaudit_v2",
    "audit_status": "COMPLETE",
    "issue_count": issue_count,
    "baseline_issue_count": 104,
    "issue_reduction": 104 - issue_count,
    "pc_home_issue_count": counts["pc_home"],
    "mobile_home_issue_count": counts["mobile_home"],
    "pc_category_issue_count": counts["pc_category"],
    "mobile_category_issue_count": counts["mobile_category"],
    "pc_article_issue_count": counts["pc_article"],
    "mobile_article_issue_count": counts["mobile_article"],
    "pc_platform_issue_count": counts["pc_platform"],
    "mobile_platform_issue_count": counts["mobile_platform"],
    "robots_issue_count": len(robots_issues),
    "sitemap_issue_count": len(sitemap_issues),
    "legacy_external_dependency_count": legacy_external_dependency_count,
    "home_http": code("home"),
    "mobile_home_http": code("mobile_home"),
    "category7_http": code("category"),
    "mobile_category7_http": code("mobile_category"),
    "article91_http": code("article"),
    "mobile_article91_http": code("mobile_article"),
    "platform19_http": code("platform"),
    "mobile_platform19_http": code("mobile_platform"),
    "robots_http": robots_http,
    "sitemap_http": sitemap_http,
    "remaining_issue_classes": sorted(set(
        x for arr in issues_by_page.values() for x in arr
    ) | set(robots_issues) | set(sitemap_issues) | ({"legacy_external_dependency"} if legacy_external_dependency_count else set())),
    "blocking_item": "NONE",
    "secrets_disclosed": False,
}
with out.open("w", encoding="utf-8") as f:
    json.dump(payload, f, ensure_ascii=False, indent=2, sort_keys=True)
    f.write("\n")
PY

echo "WHOLE_SITE_SEO_REAUDIT_V2=COMPLETE"
