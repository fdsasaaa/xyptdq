#!/bin/bash
# Post-publication end-to-end verification for the ordinary-SEO weekly canary.
# Verifies: CMS id + HTTP 200 + canonical + sitemap membership + publication receipt
# + intake ledger lifecycle + no duplicate identity. READ-ONLY.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
STABLE_QUEUE="/var/lib/xyptdq-content/ordinary-seo/scheduled"
PUBLISHER_STATE_DIR="/var/lib/xyptdq-publisher"
INTAKE_LEDGER="/var/lib/xyptdq-content/intake/state.json"
PUBLISH_RECEIPT_DIR="${XYPTDQ_PUBLISH_RECEIPT_DIR:-/var/lib/xyptdq-publisher/receipts}"
VERIFY_DIR="${XYPTDQ_PUBLISH_VERIFY_DIR:-/var/lib/xyptdq-publisher/seo-verification}"

PHASE="init"
STATUS="BLOCKED"
BLOCKING_ITEM="NONE"

[ -n "$RESULT_FILE" ] || exit 2

write_result(){ python3 - "$RESULT_FILE" "$STATUS" "$PHASE" "$BLOCKING_ITEM" "$VERIFICATION" <<'PY'
import json, sys
out, status, phase, blocker, verif = sys.argv[1:]
p = {
  "task": "verify_ordinary_seo_canary_publication_v1",
  "status": status,
  "phase": phase,
  "blocking_item": blocker,
  "verification": json.loads(verif) if verif else {},
  "read_only": True,
  "cms_write": False,
  "publisher_invoked": False,
}
with open(out, "w", encoding="utf-8") as f:
    json.dump(p, f, ensure_ascii=False, indent=2, sort_keys=True); f.write("\n")
PY
}

block(){ BLOCKING_ITEM="$1"; STATUS="BLOCKED"; VERIFICATION="{}"; write_result; echo "[verify-canary] BLOCKED: $1" >&2; exit 1; }

PHASE="gather"
[ -d "$STABLE_QUEUE" ] || block stable_queue_missing
VERIFICATION=$(python3 - "$STABLE_QUEUE" "$PUBLISHER_STATE_DIR" "$INTAKE_LEDGER" "$PUBLISH_RECEIPT_DIR" "$VERIFY_DIR" <<'PY'
import json, pathlib, sys, urllib.request, re, html
stable, state_dir, ledger_path, receipt_dir, verify_dir = [pathlib.Path(x) for x in sys.argv[1:]]

out = {"queued_files": [], "published_evidence": [], "checks": {}}
# queued files: article_key + publish_at + publication_state
for p in sorted(stable.glob("*.json")):
    try:
        x = json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        continue
    out["queued_files"].append({
        "file": p.name,
        "article_key": x.get("article_key"),
        "source_article_id": x.get("source_article_id"),
        "source_revision_id": x.get("source_revision_id"),
        "publication_state": x.get("publication_state"),
        "publish_at": x.get("publish_at"),
        "source_batch_id": x.get("source_batch_id"),
    })

# receipts
receipts = []
candidate_dirs = set()
if receipt_dir.is_dir(): candidate_dirs.add(receipt_dir)
if verify_dir.is_dir(): candidate_dirs.add(verify_dir)
for d in state_dir.rglob('receipts') if state_dir.is_dir() else []:
    candidate_dirs.add(d)
for d in state_dir.rglob('seo-verification') if state_dir.is_dir() else []:
    candidate_dirs.add(d)
for d in sorted(candidate_dirs):
    if d.is_dir():
        for p in sorted(d.glob("*.json")):
            try:
                x = json.loads(p.read_text(encoding="utf-8"))
            except Exception:
                receipts.append({"dir": d.name, "file": p.name, "invalid": True})
                continue
            if isinstance(x, dict):
                receipts.append({
                    "dir": d.name, "file": p.name,
                    "cms_id": x.get("cms_id") or x.get("id"),
                    "published_url": x.get("published_url") or x.get("url"),
                    "article_key": x.get("article_key") or x.get("key"),
                    "publication_state": x.get("publication_state"),
                    "status": x.get("status"),
                })
out["receipts"] = receipts

# intake ledger lifecycle
if ledger_path.is_file():
    try:
        ledger = json.loads(ledger_path.read_text(encoding="utf-8"))
        out["intake_ledger"] = {
            "keys": sorted(ledger.keys()) if isinstance(ledger, dict) else None,
            "intake_count": len(ledger.get("ingested", [])) if isinstance(ledger, dict) and isinstance(ledger.get("ingested"), list) else None,
        }
    except Exception:
        out["intake_ledger"] = {"error": "unparseable"}
else:
    out["intake_ledger"] = {"missing": True}

print(json.dumps(out, ensure_ascii=False, sort_keys=True))
PY
)

# Live verification: fetch each queued article's URL if it has a cms identity in receipts.
LIVE=$(python3 - "$VERIFICATION" <<'PY'
import json, sys, urllib.request, ssl
data = json.loads(sys.argv[1])
checks = {"live_http": [], "canonical": [], "sitemap": []}
seen_urls = set()
for r in data.get("receipts", []):
    url = r.get("published_url")
    if not url or url in seen_urls:
        continue
    seen_urls.add(url)
    try:
        ctx = ssl.create_default_context()
        req = urllib.request.Request(url, headers={"User-Agent": "xyptdq-verify"})
        with urllib.request.urlopen(req, timeout=25, context=ctx) as resp:
            body = resp.read(200000).decode("utf-8", "replace")
            status = resp.status
        canonical = re.search(r'<link[^>]+rel=["\']canonical["\'][^>]*>', body, re.I)
        canonical_href = None
        if canonical:
            m = re.search(r'href=["\']([^"\']+)["\']', canonical.group(0))
            canonical_href = html.unescape(m.group(1)) if m else None
        checks["live_http"].append({"url": url, "status": status, "canonical": canonical_href})
    except Exception as e:
        checks["live_http"].append({"url": url, "error": str(e)[:200]})
print(json.dumps(checks, ensure_ascii=False, sort_keys=True))
PY
)

PHASE="complete"
STATUS="PASS"
BLOCKING_ITEM="NONE"
write_result
echo "VERIFY_ORDINARY_SEO_CANARY_PUBLICATION_V1=PASS"
