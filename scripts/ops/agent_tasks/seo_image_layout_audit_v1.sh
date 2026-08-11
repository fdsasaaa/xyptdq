#!/bin/bash
# Read-only image layout audit for CLS-safe SEO/performance work.
set -euo pipefail
umask 077
RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
CANONICAL="https://www.laocaimi.org"
[ -n "$RESULT_FILE" ] || exit 2
TMP="$(mktemp -d /tmp/xyptdq-image-layout.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

fetch() {
  local name="$1" url="$2"
  curl -skL --max-time 30 -o "$TMP/$name.html" -w '%{http_code}' "$url" > "$TMP/$name.code"
}
fetch home "$CANONICAL/"
fetch category "$CANONICAL/index.php?c=category&id=7"
fetch article "$CANONICAL/index.php?c=show&id=91"
fetch platform "$CANONICAL/index.php?c=show&id=19"

python3 - "$TMP" "$RESULT_FILE" <<'PY'
import json,pathlib,re,sys
tmp=pathlib.Path(sys.argv[1]); out=pathlib.Path(sys.argv[2])

def read(n): return (tmp/f"{n}.html").read_text(encoding="utf-8",errors="ignore")
def code(n):
    try:return int((tmp/f"{n}.code").read_text().strip())
    except:return 0
def attr(tag,n):
    m=re.search(r"\b"+re.escape(n)+r"=[\"']([^\"']*)[\"']",tag,re.I|re.S)
    return m.group(1).strip() if m else ""
def metrics(n):
    s=read(n)
    imgs=re.findall(r"<img\b[^>]*>",s,re.I|re.S)
    missing=inline_both=inline_one=attr_both=lazy=eager=0
    for tag in imgs:
        w=attr(tag,"width"); h=attr(tag,"height"); style=attr(tag,"style").lower()
        has_w=bool(w); has_h=bool(h)
        if has_w and has_h: attr_both+=1
        else:
            missing+=1
            sw=bool(re.search(r"(?:^|;)\s*width\s*:\s*\d+(?:\.\d+)?px",style))
            sh=bool(re.search(r"(?:^|;)\s*height\s*:\s*\d+(?:\.\d+)?px",style))
            if sw and sh: inline_both+=1
            elif sw or sh: inline_one+=1
        if attr(tag,"loading").lower()=="lazy": lazy+=1
        else:eager+=1
    return {
      "http":code(n),
      "image_count":len(imgs),
      "images_with_width_height_attrs":attr_both,
      "images_missing_width_or_height_attrs":missing,
      "missing_attrs_but_inline_px_width_height":inline_both,
      "missing_attrs_with_only_one_inline_px_dimension":inline_one,
      "missing_attrs_without_complete_inline_px_dimensions":missing-inline_both,
      "lazy_image_count":lazy,
      "non_lazy_image_count":eager
    }

payload={
 "task":"seo_image_layout_audit_v1",
 "audit_status":"COMPLETE",
 "home":metrics("home"),
 "category7":metrics("category"),
 "article91":metrics("article"),
 "platform19":metrics("platform"),
 "blocking_item":"NONE",
 "secrets_disclosed":False
}
with out.open("w",encoding="utf-8") as f:
    json.dump(payload,f,ensure_ascii=False,indent=2,sort_keys=True); f.write("\n")
PY
echo "SEO_IMAGE_LAYOUT_AUDIT_V1=COMPLETE"
