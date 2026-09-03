#!/bin/bash
# Strict read-only E2E verification for first natural ordinary-SEO publication.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
STABLE_QUEUE="/var/lib/xyptdq-content/ordinary-seo/scheduled"
INTAKE_LEDGER="/var/lib/xyptdq-content/intake/state.json"
ORDINARY_ROOT="/var/lib/xyptdq-publisher/ordinary-seo"
PUBLISHER_ROOT="/var/lib/xyptdq-publisher"
PUBLISHER_CRON="/etc/cron.d/xyptdq-publisher"
PROMOTION_CRON="/etc/cron.d/xyptdq-promotion"
SITEMAP="/www/wwwroot/59.110.217.6/sitemap.xml"

TARGET_ARTICLE="LCM-ANGLE-0b6f9c192c45dc31"
TARGET_REV="LCM-ANGLE-0b6f9c192c45dc31:public-r1"
TARGET_BATCH="DAILY-20260901"
TARGET_PUBLISH_AT="2026-09-03T10:00:00+08:00"

[ -n "$RESULT_FILE" ] || exit 2

python3 - "$RESULT_FILE" "$STABLE_QUEUE" "$INTAKE_LEDGER" "$ORDINARY_ROOT" "$PUBLISHER_ROOT" "$PUBLISHER_CRON" "$PROMOTION_CRON" "$SITEMAP" "$TARGET_ARTICLE" "$TARGET_REV" "$TARGET_BATCH" "$TARGET_PUBLISH_AT" <<'PY'
import json, pathlib, sys, urllib.request, ssl, re, html
from datetime import datetime, timezone

(out_path, stable_s, ledger_s, ordinary_s, publisher_s, pubcron_s, promocron_s,
 sitemap_s, target_article, target_rev, target_batch, target_publish_at) = sys.argv[1:]
stable = pathlib.Path(stable_s); ledger_path = pathlib.Path(ledger_s)
ordinary = pathlib.Path(ordinary_s); publisher = pathlib.Path(publisher_s)
pubcron = pathlib.Path(pubcron_s); promocron = pathlib.Path(promocron_s)
sitemap_path = pathlib.Path(sitemap_s)

result = {
 "task":"verify_ordinary_seo_canary_publication_v2",
 "status":"BLOCKED","phase":"gather","blocking_item":"NONE",
 "read_only":True,"cms_write":False,"publisher_invoked":False,"cron_write":False,
 "target":{"source_article_id":target_article,"source_revision_id":target_rev,
           "source_batch_id":target_batch,"publish_at":target_publish_at},
 "checks":{}, "evidence":{}
}
fails=[]
def fail(x): fails.append(x)

queue_matches=[]
if stable.is_dir():
    for p in stable.glob("*.json"):
        try: x=json.loads(p.read_text(encoding="utf-8"))
        except Exception: continue
        blob=json.dumps(x,ensure_ascii=False)
        if target_article in blob or target_rev in blob:
            queue_matches.append({"file":p.name,"publication_state":x.get("publication_state"),
                                  "publish_at":x.get("publish_at"),"article_key":x.get("article_key")})
result["evidence"]["queue_matches"]=queue_matches
if any((m.get("publication_state") or "").lower() in ("scheduled","pending","due") for m in queue_matches):
    fail("target_still_queued_unpublished")

matches=[]
if publisher.is_dir():
    for p in publisher.rglob("*.json"):
        try:
            txt=p.read_text(encoding="utf-8")
            if target_article not in txt and target_rev not in txt: continue
            x=json.loads(txt)
            matches.append((p,x))
        except Exception:
            continue

def walk(obj):
    if isinstance(obj,dict):
        yield obj
        for v in obj.values(): yield from walk(v)
    elif isinstance(obj,list):
        for v in obj: yield from walk(v)

rows=[]
for p,x in matches:
    for d in walk(x):
        blob=json.dumps(d,ensure_ascii=False)
        if target_article in blob or target_rev in blob:
            row={"path":str(p)}
            for k in ("source_article_id","source_revision_id","source_batch_id","source_content_hash",
                      "content_hash","cms_id","id","published_url","url","publication_state",
                      "published_at","status","article_key"):
                if k in d and d[k] is not None: row[k]=d[k]
            rows.append(row)
result["evidence"]["matched_records"]=rows[:100]

cms_ids=set(); urls=set(); revs=set(); batches=set(); hashes=set(); published_markers=[]
for r in rows:
    if r.get("cms_id") is not None: cms_ids.add(str(r["cms_id"]))
    if r.get("id") is not None and any(k in r for k in ("published_url","published_at","publication_state")):
        cms_ids.add(str(r["id"]))
    for k in ("published_url","url"):
        v=r.get(k)
        if isinstance(v,str) and v.startswith(("http://","https://")): urls.add(v)
    if r.get("source_revision_id"): revs.add(str(r["source_revision_id"]))
    if r.get("source_batch_id"): batches.add(str(r["source_batch_id"]))
    for k in ("source_content_hash","content_hash"):
        v=r.get(k)
        if v: hashes.add(str(v))
    st=str(r.get("publication_state") or r.get("status") or "").lower()
    if "publish" in st or r.get("published_at"): published_markers.append(r)

result["evidence"]["cms_ids"]=sorted(cms_ids)
result["evidence"]["published_urls"]=sorted(urls)
result["evidence"]["revision_ids"]=sorted(revs)
result["evidence"]["batch_ids"]=sorted(batches)
result["evidence"]["content_hashes"]=sorted(hashes)
if not cms_ids: fail("cms_id_missing")
if len(cms_ids)!=1: fail("duplicate_cms_identity")
if not urls: fail("published_url_missing")
if len(urls)!=1: fail("duplicate_published_url_identity")
if target_rev not in revs: fail("source_revision_id_not_verified")
if target_batch not in batches: fail("source_batch_id_not_verified")
if not hashes: fail("source_content_hash_missing")
if not published_markers: fail("published_state_missing")

receipt_paths=sorted({r["path"] for r in rows if "receipt" in r["path"].lower()})
verify_paths=sorted({r["path"] for r in rows if "verification" in r["path"].lower()})
result["evidence"]["receipt_paths"]=receipt_paths
result["evidence"]["seo_verification_paths"]=verify_paths
if not receipt_paths: fail("publication_receipt_missing")
if not verify_paths: fail("live_seo_verification_missing")

ledger_txt=""
if ledger_path.is_file(): ledger_txt=ledger_path.read_text(encoding="utf-8",errors="replace")
result["checks"]["intake_ledger_target_revision"]=target_rev in ledger_txt
result["checks"]["intake_ledger_content_hash"]=any(h in ledger_txt for h in hashes) if hashes else False
if target_rev not in ledger_txt: fail("intake_ledger_revision_missing")
if hashes and not any(h in ledger_txt for h in hashes): fail("intake_ledger_hash_missing")
if not any(tok in ledger_txt.lower() for tok in ("published","live")): fail("intake_ledger_published_lifecycle_missing")

live=[]
ctx=ssl.create_default_context()
for url in sorted(urls):
    item={"url":url}
    try:
        req=urllib.request.Request(url,headers={"User-Agent":"xyptdq-e2e-verify/2"})
        with urllib.request.urlopen(req,timeout=30,context=ctx) as resp:
            body=resp.read(500000).decode("utf-8","replace"); item["http_status"]=resp.status
        m=re.search(r'<link[^>]+rel=["\']canonical["\'][^>]*>',body,re.I)
        href=None
        if m:
            m2=re.search(r'href=["\']([^"\']+)["\']',m.group(0),re.I)
            href=html.unescape(m2.group(1)) if m2 else None
        item["canonical"]=href
        robots=" ".join(re.findall(r'<meta[^>]+name=["\']robots["\'][^>]*>',body,re.I))
        item["noindex"]=bool(re.search(r'noindex',robots,re.I))
        if item["http_status"]!=200: fail("live_http_not_200")
        if href != url: fail("canonical_not_self")
        if item["noindex"]: fail("live_page_noindex")
    except Exception as e:
        item["error"]=str(e)[:300]; fail("live_http_fetch_failed")
    live.append(item)
result["evidence"]["live"]=live

sitemap_txt=sitemap_path.read_text(encoding="utf-8",errors="replace") if sitemap_path.is_file() else ""
for url in urls:
    if url not in sitemap_txt: fail("sitemap_membership_missing")
result["checks"]["sitemap_membership"]=bool(urls) and all(u in sitemap_txt for u in urls)

pubtxt=pubcron.read_text(encoding="utf-8",errors="replace") if pubcron.is_file() else ""
expected_source="XYPTDQ_PUBLISH_SOURCE=/var/lib/xyptdq-content/ordinary-seo/scheduled"
expected_state="XYPTDQ_PUBLISH_STATE=/var/lib/xyptdq-publisher/ordinary-seo/state.json"
expected_lock="XYPTDQ_PUBLISH_LOCK=/var/lib/xyptdq-publisher/ordinary-seo/publisher.lock"
for name,val in (("publisher_source",expected_source),("publisher_state",expected_state),("publisher_lock",expected_lock)):
    ok=val in pubtxt; result["checks"][name]=ok
    if not ok: fail(name+"_wrong")
allcron=""
for p in list(pathlib.Path("/etc/cron.d").glob("*"))+[pathlib.Path("/etc/crontab")]:
    try: allcron += "\n"+p.read_text(encoding="utf-8",errors="replace")
    except Exception: pass
active=[ln for ln in allcron.splitlines() if ln.strip() and not ln.lstrip().startswith("#")]
pub_count=sum("run_scheduled_publish.sh" in ln for ln in active)
promo_count=sum("promote_ordinary_seo_v1.sh" in ln for ln in active)
result["checks"]["publisher_cron_singleton_count"]=pub_count
result["checks"]["promotion_cron_active_count_before_enable"]=promo_count
if pub_count!=1: fail("publisher_cron_not_singleton")
if promo_count!=0: fail("promotion_cron_was_not_held_before_e2e")

legacy=[]
due=datetime.fromisoformat(target_publish_at).astimezone(timezone.utc).timestamp()
for p in publisher.glob("*.json"):
    if p.is_file() and ordinary not in p.parents:
        try:
            txt=p.read_text(encoding="utf-8",errors="replace")
            legacy.append({"path":str(p),"mtime":p.stat().st_mtime,"contains_target":target_article in txt or target_rev in txt})
            if target_article in txt or target_rev in txt: fail("legacy_cf50_state_contains_ordinary_target")
            if "state" in p.name.lower() and p.stat().st_mtime >= due: fail("legacy_cf50_state_changed_after_canary_due")
        except Exception: pass
result["evidence"]["legacy_state"]=legacy

result["phase"]="complete"
if fails:
    result["status"]="BLOCKED"; result["blocking_item"]=fails[0]; result["failures"]=sorted(set(fails))
else:
    result["status"]="PASS"; result["blocking_item"]="NONE"
    result["conclusions"]={"FIRST_NATURAL_PUBLICATION":"PASS","END_TO_END_WEBSITE_CANARY":"PASS"}
pathlib.Path(out_path).write_text(json.dumps(result,ensure_ascii=False,indent=2,sort_keys=True)+"\n",encoding="utf-8")
print(json.dumps(result,ensure_ascii=False,sort_keys=True))
raise SystemExit(0 if result["status"]=="PASS" else 1)
PY
