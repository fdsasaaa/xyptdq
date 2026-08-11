#!/bin/bash
# Read-only intrinsic image dimension audit for unresolved layout candidates.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
CANONICAL="https://www.laocaimi.org"
[ -n "$RESULT_FILE" ] || exit 2

TMP="$(mktemp -d /tmp/xyptdq-image-intrinsic.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

fetch() {
  local name="$1" url="$2"
  curl -skL --max-time 30 -o "$TMP/$name.html" -w '%{http_code}' "$url" > "$TMP/$name.code"
}
fetch home "$CANONICAL/"
fetch category7 "$CANONICAL/index.php?c=category&id=7"
fetch article91 "$CANONICAL/index.php?c=show&id=91"
fetch platform19 "$CANONICAL/index.php?c=show&id=19"

python3 - "$TMP" "$RESULT_FILE" "$CANONICAL" <<'PY'
import hashlib, json, pathlib, re, subprocess, sys, urllib.parse

tmp=pathlib.Path(sys.argv[1])
out=pathlib.Path(sys.argv[2])
canonical=sys.argv[3].rstrip('/') + '/'

def attr(tag,name):
    m=re.search(r'\b'+re.escape(name)+r'=["\']([^"\']*)["\']',tag,re.I|re.S)
    return m.group(1).strip() if m else ''

def inline_complete(tag):
    style=attr(tag,'style').lower()
    sw=bool(re.search(r'(?:^|;)\s*width\s*:\s*\d+(?:\.\d+)?px',style))
    sh=bool(re.search(r'(?:^|;)\s*height\s*:\s*\d+(?:\.\d+)?px',style))
    return sw and sh

def safe_context(tag):
    return {
      'alt': attr(tag,'alt')[:80],
      'class': attr(tag,'class')[:80],
      'has_inline_complete_px_dimensions': inline_complete(tag)
    }

candidates=[]
pages=['home','category7','article91','platform19']
for page in pages:
    html=(tmp/f'{page}.html').read_text(encoding='utf-8',errors='ignore')
    imgs=re.findall(r'<img\b[^>]*>',html,re.I|re.S)
    for idx,tag in enumerate(imgs,1):
        w=attr(tag,'width'); h=attr(tag,'height')
        if w and h:
            continue
        if inline_complete(tag):
            continue
        src=attr(tag,'src')
        absolute=urllib.parse.urljoin(canonical,src)
        parsed=urllib.parse.urlparse(absolute)
        same_origin=(parsed.scheme in ('http','https') and parsed.netloc.lower()=='www.laocaimi.org')
        item={
          'page':page,
          'image_index':idx,
          **safe_context(tag),
          'same_origin':same_origin,
          'src_sha256':hashlib.sha256(absolute.encode('utf-8')).hexdigest() if absolute else '',
          'download_status':'SKIPPED',
          'intrinsic_width':0,
          'intrinsic_height':0,
          'mime':''
        }
        if parsed.scheme in ('http','https') and parsed.netloc:
            dest=tmp/f'img-{page}-{idx}.bin'
            proc=subprocess.run(
                ['curl','-skL','--max-time','20','--max-filesize','10485760','-o',str(dest),'-w','%{http_code}',absolute],
                stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True
            )
            http=proc.stdout.strip()
            if proc.returncode==0 and http=='200' and dest.exists() and dest.stat().st_size>0:
                php=subprocess.run(
                    ['php','-r',
                     '$s=@getimagesize($argv[1]); if(!$s){exit(2);} echo $s[0]."\\t".$s[1]."\\t".($s["mime"]??"");',
                     str(dest)],
                    stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True
                )
                if php.returncode==0:
                    parts=php.stdout.strip().split('\t')
                    if len(parts)>=2 and parts[0].isdigit() and parts[1].isdigit():
                        item['intrinsic_width']=int(parts[0]); item['intrinsic_height']=int(parts[1])
                        item['mime']=parts[2][:40] if len(parts)>2 else ''
                        item['download_status']='PASS'
                    else:
                        item['download_status']='DIMENSION_PARSE_FAILED'
                else:
                    item['download_status']='GETIMAGESIZE_FAILED'
            else:
                item['download_status']='DOWNLOAD_FAILED'
        candidates.append(item)

http={}
for p in pages:
    try:http[p]=int((tmp/f'{p}.code').read_text().strip())
    except:http[p]=0

known=sum(1 for c in candidates if c['intrinsic_width']>0 and c['intrinsic_height']>0)
payload={
  'task':'seo_image_intrinsic_audit_v1',
  'audit_status':'COMPLETE',
  'http':http,
  'unresolved_candidate_count':len(candidates),
  'intrinsic_dimensions_resolved_count':known,
  'intrinsic_dimensions_unresolved_count':len(candidates)-known,
  'candidates':candidates,
  'blocking_item':'NONE',
  'secrets_disclosed':False,
  'raw_urls_disclosed':False
}
with out.open('w',encoding='utf-8') as f:
    json.dump(payload,f,ensure_ascii=False,indent=2,sort_keys=True)
    f.write('\n')
PY

echo "SEO_IMAGE_INTRINSIC_AUDIT_V1=COMPLETE"
