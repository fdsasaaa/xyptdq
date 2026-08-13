#!/bin/bash
# Read-only Phase 2 production preflight for the current tzjq architecture.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
CANONICAL="https://www.laocaimi.org"
REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
[ -n "$RESULT_FILE" ] || exit 2

TMP="$(mktemp -d /tmp/xyptdq-phase2-preflight.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

fetch_follow() {
  local name="$1" url="$2" ua="${3:-}"
  if [ -n "$ua" ]; then
    curl -skL --max-time 30 -A "$ua" -o "$TMP/$name.body" -w '%{http_code}\n%{url_effective}\n' "$url" > "$TMP/$name.meta"
  else
    curl -skL --max-time 30 -o "$TMP/$name.body" -w '%{http_code}\n%{url_effective}\n' "$url" > "$TMP/$name.meta"
  fi
}

fetch_no_follow_headers() {
  local name="$1" url="$2"
  curl -sk --max-time 30 -D "$TMP/$name.headers" -o /dev/null -w '%{http_code}\n' "$url" > "$TMP/$name.code"
}

MOBILE_UA='Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 Chrome/134 Mobile Safari/537.36'

fetch_follow home "$CANONICAL/"
fetch_follow mobile_home "$CANONICAL/" "$MOBILE_UA"
fetch_follow tzjq "$CANONICAL/index.php?c=category&dir=tzjq"
fetch_follow mobile_tzjq "$CANONICAL/index.php?c=category&dir=tzjq" "$MOBILE_UA"
fetch_follow article91 "$CANONICAL/index.php?c=show&id=91"
fetch_follow mobile_article91 "$CANONICAL/index.php?c=show&id=91" "$MOBILE_UA"
fetch_follow platform19 "$CANONICAL/index.php?c=show&id=19"
fetch_follow robots "$CANONICAL/robots.txt"
fetch_follow sitemap "$CANONICAL/sitemap.xml"
fetch_no_follow_headers old_seo_articles "$CANONICAL/index.php?c=category&dir=seo-articles"

CRON_PRESENT=0
if crontab -l 2>/dev/null | grep -Eq 'auto_publish_filequeue|run_scheduled_publish'; then
  CRON_PRESENT=1
fi
SCHEDULED_JSON_COUNT=0
if [ -d "$REPO_ROOT/content/scheduled" ]; then
  SCHEDULED_JSON_COUNT="$(find "$REPO_ROOT/content/scheduled" -maxdepth 1 -type f -name '*.json' | wc -l | tr -d ' ')"
fi

python3 - "$TMP" "$RESULT_FILE" "$CANONICAL" "$CRON_PRESENT" "$SCHEDULED_JSON_COUNT" <<'PY'
import json, pathlib, re, sys

tmp = pathlib.Path(sys.argv[1])
out = pathlib.Path(sys.argv[2])
canonical = sys.argv[3]
cron_present = int(sys.argv[4])
scheduled_count = int(sys.argv[5])


def body(name):
    p = tmp / f"{name}.body"
    return p.read_text(encoding="utf-8", errors="ignore") if p.exists() else ""


def meta(name):
    p = tmp / f"{name}.meta"
    lines = p.read_text(encoding="utf-8", errors="ignore").splitlines() if p.exists() else []
    try:
        code = int(lines[0])
    except Exception:
        code = 0
    effective = lines[1].strip() if len(lines) > 1 else ""
    return code, effective


def canonical_href(html):
    vals = []
    for tag in re.findall(r"<link\b[^>]*>", html, re.I | re.S):
        rel = re.search(r"\brel=[\"']([^\"']+)[\"']", tag, re.I)
        if not rel or "canonical" not in rel.group(1).lower().split():
            continue
        href = re.search(r"\bhref=[\"']([^\"']+)[\"']", tag, re.I | re.S)
        if href:
            vals.append(href.group(1).strip())
    return vals


def meta_description_count(html):
    count = 0
    for tag in re.findall(r"<meta\b[^>]*>", html, re.I | re.S):
        name = re.search(r"\bname=[\"']([^\"']+)[\"']", tag, re.I)
        content = re.search(r"\bcontent=[\"']([^\"']*)[\"']", tag, re.I | re.S)
        if name and name.group(1).strip().lower() == "description" and content and content.group(1).strip():
            count += 1
    return count


def page_audit(name, require_jsonld=False):
    html = body(name)
    code, effective = meta(name)
    issues = []
    if code != 200:
        issues.append("http_not_200")
        return {"http": code, "effective_url": effective, "issues": issues}
    if len(re.findall(r"<title\b", html, re.I)) != 1:
        issues.append("title_not_one")
    if meta_description_count(html) != 1:
        issues.append("description_missing_or_duplicate")
    if len(re.findall(r"<h1\b", html, re.I)) != 1:
        issues.append("h1_not_one")
    canons = canonical_href(html)
    if len(canons) != 1:
        issues.append("canonical_missing_or_duplicate")
    elif not canons[0].startswith(canonical):
        issues.append("canonical_host_mismatch")
    if re.search(r"<meta\b[^>]*name=[\"']robots[\"'][^>]*content=[\"'][^\"']*noindex", html, re.I | re.S):
        issues.append("noindex_present")
    if require_jsonld and not re.search(r"application/ld\+json", html, re.I):
        issues.append("jsonld_missing")
    return {"http": code, "effective_url": effective, "canonical": canons[0] if len(canons) == 1 else None, "issues": issues}

pages = {
    "pc_home": page_audit("home", True),
    "mobile_home": page_audit("mobile_home", False),
    "pc_tzjq": page_audit("tzjq", True),
    "mobile_tzjq": page_audit("mobile_tzjq", True),
    "pc_article91": page_audit("article91", True),
    "mobile_article91": page_audit("mobile_article91", True),
    "platform19": page_audit("platform19", True),
}

robots_code, _ = meta("robots")
robots = body("robots")
robots_issues = []
if robots_code != 200:
    robots_issues.append("robots_http_not_200")
if "Sitemap: https://www.laocaimi.org/sitemap.xml" not in robots:
    robots_issues.append("canonical_sitemap_not_advertised")
if re.search(r"(?im)^\s*Disallow:\s*/\s*$", robots):
    robots_issues.append("robots_disallow_all")

sitemap_code, _ = meta("sitemap")
sitemap = body("sitemap")
sitemap_issues = []
if sitemap_code != 200:
    sitemap_issues.append("sitemap_http_not_200")
locs = re.findall(r"<loc>(.*?)</loc>", sitemap, re.I | re.S)
locs = [x.strip().replace("&amp;", "&") for x in locs]
if not locs:
    sitemap_issues.append("sitemap_has_no_urls")
if any(not x.startswith(canonical) for x in locs):
    sitemap_issues.append("sitemap_noncanonical_host")

migrated_ids = [85, 86, 88, 91]
migrated_present = {str(i): any(f"c=show&id={i}" in x for x in locs) for i in migrated_ids}
tzjq_present = any("c=category&dir=tzjq" in x for x in locs)
old_seo_present = any("dir=seo-articles" in x for x in locs)

try:
    old_code = int((tmp / "old_seo_articles.code").read_text().strip())
except Exception:
    old_code = 0
old_headers = (tmp / "old_seo_articles.headers").read_text(encoding="utf-8", errors="ignore") if (tmp / "old_seo_articles.headers").exists() else ""
loc = re.search(r"(?im)^location:\s*(\S+)\s*$", old_headers)
old_location = loc.group(1).strip() if loc else ""
old_redirect_ok = old_code in (301, 302, 307, 308) and ("dir=tzjq" in old_location or old_location.endswith("/tzjq"))

page_issue_count = sum(len(x["issues"]) for x in pages.values())
issue_classes = sorted(set(x for p in pages.values() for x in p["issues"]) | set(robots_issues) | set(sitemap_issues))
if not old_redirect_ok:
    issue_classes.append("old_seo_articles_redirect_regression")
if old_seo_present:
    issue_classes.append("old_seo_articles_still_in_sitemap")
if not tzjq_present:
    issue_classes.append("tzjq_missing_from_sitemap")
if not all(migrated_present.values()):
    issue_classes.append("migrated_article_missing_from_sitemap")
issue_classes = sorted(set(issue_classes))

payload = {
    "task": "phase2_content_preflight_v3",
    "audit_status": "COMPLETE",
    "pages": pages,
    "robots_http": robots_code,
    "robots_issues": robots_issues,
    "sitemap_http": sitemap_code,
    "sitemap_url_count": len(locs),
    "sitemap_issues": sitemap_issues,
    "tzjq_in_sitemap": tzjq_present,
    "old_seo_articles_in_sitemap": old_seo_present,
    "migrated_articles_in_sitemap": migrated_present,
    "old_seo_articles_http": old_code,
    "old_seo_articles_redirect_to_tzjq": old_redirect_ok,
    "publisher_cron_present": bool(cron_present),
    "repository_scheduled_json_count": scheduled_count,
    "page_issue_count": page_issue_count,
    "remaining_issue_classes": issue_classes,
    "blocking_item": "NONE" if not issue_classes else "REGRESSION_REVIEW_REQUIRED",
    "cms_write_attempted": False,
    "publisher_invoked": False,
    "scheduled_queue_consumed": False,
    "secrets_disclosed": False,
}
out.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

echo "PHASE2_CONTENT_PREFLIGHT_V3=COMPLETE"
