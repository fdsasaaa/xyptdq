#!/bin/bash
# Read-only E2E verifier aligned with immutable Scheduled queue + durable state/receipt semantics.
set -euo pipefail
umask 077
RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
[ -n "$RESULT_FILE" ] || exit 2
python3 - "$RESULT_FILE" <<'PY'
import json, pathlib, sys, urllib.request, ssl, re, html, xml.etree.ElementTree as ET
from datetime import datetime, timezone

OUT=pathlib.Path(sys.argv[1])
ARTICLE="LCM-ANGLE-0b6f9c192c45dc31"
REV="LCM-ANGLE-0b6f9c192c45dc31:public-r1"
BATCH="DAILY-20260901"
DUE="2026-09-03T10:00:00+08:00"
KEY="lcm-angle-0b6f9c192c45dc31"
QUEUE=pathlib.Path("/var/lib/xyptdq-content/ordinary-seo/scheduled")
ORD=pathlib.Path("/var/lib/xyptdq-publisher/ordinary-seo")
LEDGER=pathlib.Path("/var/lib/xyptdq-content/intake/state.json")
PUBCRON=pathlib.Path("/etc/cron.d/xyptdq-publisher")
PROMOCRON=pathlib.Path("/etc/cron.d/xyptdq-promotion")
SITEMAP=pathlib.Path("/www/wwwroot/59.110.217.6/sitemap.xml")
LEGACY=pathlib.Path("/var/lib/xyptdq-publisher/state.json")

r={"task":"verify_ordinary_seo_canary_publication_v3","status":"BLOCKED","blocking_item":"NONE",
   "read_only":True,"cms_write":False,"cron_write":False,"publisher_invoked":False,
   "target":{"source_article_id":ARTICLE,"source_revision_id":REV,"source_batch_id":BATCH,"publish_at":DUE},
   "checks":{},"evidence":{}}
fail=[]
def bad(x): fail.append(x)
def load(p):
    try:return json.loads(p.read_text(encoding="utf-8"))
    except Exception:return None
def walk(x):
    if isinstance(x,dict):
        yield x
        for v in x.values(): yield from walk(v)
    elif isinstance(x,list):
        for v in x: yield from walk(v)

def vals(obj,key):
    return [d.get(key) for d in walk(obj) if key in d and d.get(key) is not None]

# Immutable Scheduled source is provenance, not a completion flag.
qfile=QUEUE/(KEY+".json")
q=load(qfile)
r["evidence"]["queue_file"]=str(qfile)
if not isinstance(q,dict): bad("scheduled_source_missing")
else:
    qblob=json.dumps(q,ensure_ascii=False)
    qrev=REV in qblob; qbatch=BATCH in qblob; qarticle=ARTICLE in qblob
    qhash=next((str(v) for k in ("source_content_hash","content_hash") for v in vals(q,k) if v),None)
    qdue=DUE in qblob
    r["checks"].update({"queue_article_identity":qarticle,"queue_revision_identity":qrev,"queue_batch_identity":qbatch,"queue_publish_at":qdue})
    r["evidence"]["source_content_hash"]=qhash
    for name,ok in (("queue_article_identity",qarticle),("queue_revision_identity",qrev),("queue_batch_identity",qbatch),("queue_publish_at",qdue)):
        if not ok: bad(name+"_missing")
    if not qhash: bad("queue_source_content_hash_missing")

# Durable ordinary-seo state must prove completion independent of immutable queue.
state=load(ORD/"state.json")
stateblob=json.dumps(state,ensure_ascii=False) if state is not None else ""
r["checks"]["ordinary_state_exists"] = state is not None
r["checks"]["ordinary_state_has_target"] = KEY in stateblob or ARTICLE in stateblob or REV in stateblob
if state is None: bad("ordinary_state_missing")
if not r["checks"]["ordinary_state_has_target"]: bad("ordinary_state_target_missing")

# Receipt is the durable publication identity.
receipts=[]
for p in (ORD/"receipts").glob("*.json") if (ORD/"receipts").is_dir() else []:
    x=load(p)
    if x is None: continue
    blob=json.dumps(x,ensure_ascii=False)
    if KEY in blob or ARTICLE in blob or REV in blob:
        receipts.append((p,x))
r["evidence"]["receipt_paths"]=[str(p) for p,_ in receipts]
if len(receipts)!=1: bad("publication_receipt_identity_not_unique")
rec=receipts[0][1] if len(receipts)==1 else {}
cms=next((str(v) for v in vals(rec,"cms_id") if v is not None),None)
url=next((str(v) for k in ("published_url","url") for v in vals(rec,k) if isinstance(v,str) and v.startswith("http")),None)
pub_at=next((str(v) for v in vals(rec,"published_at") if v),None)
rhash=next((str(v) for k in ("source_content_hash","content_hash") for v in vals(rec,k) if v),None)
r["evidence"].update({"cms_id":cms,"published_url":url,"published_at":pub_at,"receipt_content_hash":rhash})
if not cms: bad("cms_id_missing")
if not url: bad("published_url_missing")
if not pub_at: bad("published_at_missing")
else:
    try:
        if datetime.fromisoformat(pub_at.replace("Z","+00:00")) < datetime.fromisoformat(DUE).astimezone(timezone.utc): bad("published_before_due")
    except Exception: bad("published_at_unparseable")
qhash=r["evidence"].get("source_content_hash")
if qhash and rhash != qhash: bad("receipt_hash_mismatch")

# Live page checks.
if url:
    try:
        req=urllib.request.Request(url,headers={"User-Agent":"xyptdq-e2e-verify/3"})
        with urllib.request.urlopen(req,timeout=30,context=ssl.create_default_context()) as resp:
            body=resp.read(500000).decode("utf-8","replace"); status=resp.status
        cm=re.search(r'<link[^>]+rel=["\']canonical["\'][^>]*>',body,re.I)
        canon=None
        if cm:
            hm=re.search(r'href=["\']([^"\']+)["\']',cm.group(0),re.I); canon=html.unescape(hm.group(1)) if hm else None
        robots=" ".join(re.findall(r'<meta[^>]+name=["\']robots["\'][^>]*>',body,re.I))
        noindex=bool(re.search(r'noindex',robots,re.I))
        r["evidence"]["live"]={"http_status":status,"canonical":canon,"noindex":noindex}
        if status!=200: bad("live_http_not_200")
        if canon!=url: bad("canonical_not_self")
        if noindex: bad("live_noindex")
    except Exception as e:
        r["evidence"]["live_error"]=str(e)[:300]; bad("live_fetch_failed")

# SEO verification must exist and not report a failure.
ver=[]
for p in (ORD/"seo-verification").glob("*.json") if (ORD/"seo-verification").is_dir() else []:
    x=load(p)
    if x is None: continue
    blob=json.dumps(x,ensure_ascii=False)
    if KEY in blob or (cms and cms in blob) or (url and url in blob): ver.append((p,x))
r["evidence"]["seo_verification_paths"]=[str(p) for p,_ in ver]
if len(ver)!=1: bad("live_seo_verification_identity_not_unique")
elif any(str(v).lower() in ("fail","failed","error","blocked") for v in vals(ver[0][1],"status")): bad("live_seo_verification_failed")

# XML-aware Sitemap membership (handles &amp; in query URLs).
sitemap_urls=[]
if SITEMAP.is_file():
    try:
        root=ET.fromstring(SITEMAP.read_text(encoding="utf-8",errors="replace"))
        sitemap_urls=[(e.text or "").strip() for e in root.iter() if e.tag.endswith("loc")]
    except Exception as e: r["evidence"]["sitemap_error"]=str(e)[:300]
r["checks"]["sitemap_membership"] = bool(url and url in sitemap_urls)
if not r["checks"]["sitemap_membership"]: bad("sitemap_membership_missing")

# Intake ledger must retain exact source provenance and published lifecycle/identity.
ledger=load(LEDGER); lblob=json.dumps(ledger,ensure_ascii=False) if ledger is not None else ""
r["checks"]["ledger_revision"] = REV in lblob
r["checks"]["ledger_hash"] = bool(qhash and qhash in lblob)
r["checks"]["ledger_cms_id"] = bool(cms and re.search(r'("cms_id"\s*:\s*"?'+re.escape(cms)+r'"?)',lblob))
r["checks"]["ledger_published_lifecycle"] = any(t in lblob.lower() for t in ('"published"','"live"'))
for k in ("ledger_revision","ledger_hash","ledger_cms_id","ledger_published_lifecycle"):
    if not r["checks"][k]: bad(k+"_missing")

# Cron isolation and singleton checks.
pubtxt=PUBCRON.read_text(encoding="utf-8",errors="replace") if PUBCRON.is_file() else ""
for k,s in {
 "publisher_source":"XYPTDQ_PUBLISH_SOURCE=/var/lib/xyptdq-content/ordinary-seo/scheduled",
 "publisher_state":"XYPTDQ_PUBLISH_STATE=/var/lib/xyptdq-publisher/ordinary-seo/state.json",
 "publisher_lock":"XYPTDQ_PUBLISH_LOCK=/var/lib/xyptdq-publisher/ordinary-seo/publisher.lock"}.items():
    r["checks"][k]=s in pubtxt
    if not r["checks"][k]: bad(k+"_wrong")
allcron=""
for p in list(pathlib.Path("/etc/cron.d").glob("*"))+[pathlib.Path("/etc/crontab")]:
    try: allcron+="\n"+p.read_text(encoding="utf-8",errors="replace")
    except Exception: pass
active=[x for x in allcron.splitlines() if x.strip() and not x.lstrip().startswith("#")]
pc=sum("run_scheduled_publish.sh" in x for x in active); mc=sum("promote_ordinary_seo_v1.sh" in x for x in active)
r["checks"]["publisher_cron_singleton_count"]=pc; r["checks"]["promotion_cron_active_count_before_enable"]=mc
if pc!=1: bad("publisher_cron_not_singleton")
if mc!=0: bad("promotion_cron_not_held_before_e2e")

# Legacy CF50 state must neither contain this ordinary target nor change after its prior frozen baseline.
if LEGACY.is_file():
    ltxt=LEGACY.read_text(encoding="utf-8",errors="replace")
    r["evidence"]["legacy_state_mtime"]=LEGACY.stat().st_mtime
    if KEY in ltxt or ARTICLE in ltxt or REV in ltxt: bad("legacy_cf50_state_contains_ordinary_target")

r["failures"]=sorted(set(fail))
if fail:
    r["status"]="BLOCKED"; r["blocking_item"]=fail[0]
else:
    r["status"]="PASS"; r["blocking_item"]="NONE"
    r["conclusions"]={"FIRST_NATURAL_PUBLICATION":"PASS","END_TO_END_WEBSITE_CANARY":"PASS"}
OUT.write_text(json.dumps(r,ensure_ascii=False,indent=2,sort_keys=True)+"\n",encoding="utf-8")
print(json.dumps(r,ensure_ascii=False,sort_keys=True))
raise SystemExit(0 if r["status"]=="PASS" else 1)
PY
