#!/bin/bash
# Read-only production resource/performance audit. No browser automation or production writes.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
CANONICAL="https://www.laocaimi.org"
[ -n "$RESULT_FILE" ] || exit 2

TMP="$(mktemp -d /tmp/xyptdq-perf-resource.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

fetch_page() {
  local name="$1" url="$2" ua="${3:-}"
  local args=(-skL --max-time 30 -o "$TMP/$name.html" -w '%{http_code}\t%{time_starttransfer}\t%{time_total}\t%{size_download}')
  if [ -n "$ua" ]; then
    curl "${args[@]}" -A "$ua" "$url" > "$TMP/$name.metrics"
  else
    curl "${args[@]}" "$url" > "$TMP/$name.metrics"
  fi
}

fetch_page home "$CANONICAL/"
fetch_page category7 "$CANONICAL/index.php?c=category&id=7"
fetch_page article91 "$CANONICAL/index.php?c=show&id=91"
fetch_page platform19 "$CANONICAL/index.php?c=show&id=19"
MOBILE_UA='Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 Chrome/134 Mobile Safari/537.36'
fetch_page mobile_home "$CANONICAL/" "$MOBILE_UA"

python3 - "$TMP" "$RESULT_FILE" "$CANONICAL" <<'PY'
import hashlib, html as htmlmod, json, pathlib, re, subprocess, sys, urllib.parse

tmp=pathlib.Path(sys.argv[1])
out=pathlib.Path(sys.argv[2])
canonical=sys.argv[3].rstrip('/')+'/'
canonical_host=urllib.parse.urlparse(canonical).netloc.lower()

def attr(tag,name):
    m=re.search(r'\b'+re.escape(name)+r'\s*=\s*["\']([^"\']*)["\']',tag,re.I|re.S)
    return htmlmod.unescape(m.group(1).strip()) if m else ''

def parse_metrics(name):
    raw=(tmp/f'{name}.metrics').read_text(encoding='utf-8',errors='ignore').strip().split('\t')
    try:
        return {'http':int(raw[0]),'ttfb_seconds':round(float(raw[1]),4),'total_seconds':round(float(raw[2]),4),'html_bytes':int(float(raw[3]))}
    except Exception:
        return {'http':0,'ttfb_seconds':0.0,'total_seconds':0.0,'html_bytes':0}

def head_section(s):
    m=re.search(r'<head\b[^>]*>(.*?)</head\s*>',s,re.I|re.S)
    return m.group(1) if m else ''

def resource_metrics(name):
    s=(tmp/f'{name}.html').read_text(encoding='utf-8',errors='ignore')
    head=head_section(s)
    imgs=re.findall(r'<img\b[^>]*>',s,re.I|re.S)
    scripts=re.findall(r'<script\b[^>]*>',s,re.I|re.S)
    head_scripts=re.findall(r'<script\b[^>]*>',head,re.I|re.S)
    styles=re.findall(r'<link\b[^>]*rel\s*=\s*["\'][^"\']*stylesheet[^"\']*["\'][^>]*>',s,re.I|re.S)
    lazy=sum(1 for t in imgs if attr(t,'loading').lower()=='lazy')
    eager=sum(1 for t in imgs if attr(t,'loading').lower()=='eager')
    decoding_async=sum(1 for t in imgs if attr(t,'decoding').lower()=='async')
    fetch_high=sum(1 for t in imgs if attr(t,'fetchpriority').lower()=='high')
    blocking=[]
    for t in head_scripts:
        src=attr(t,'src')
        low=t.lower()
        if src and not re.search(r'\b(?:async|defer)\b',low):
            blocking.append(src)
    images=[]
    seen=set()
    for tag in imgs:
        src=attr(tag,'src')
        if not src: continue
        absolute=urllib.parse.urljoin(canonical,src)
        if absolute in seen: continue
        seen.add(absolute)
        p=urllib.parse.urlparse(absolute)
        if p.scheme not in ('http','https') or not p.netloc: continue
        images.append((absolute,p.netloc.lower()==canonical_host))

    total_bytes=resolved=failed=0
    same_origin=sum(1 for _,same in images if same)
    external=len(images)-same_origin
    largest=[]
    for i,(url,same) in enumerate(images):
        dest=tmp/f'{name}-img-{i}.bin'
        proc=subprocess.run(['curl','-skL','--max-time','20','--max-filesize','10485760','-o',str(dest),'-w','%{http_code}\t%{content_type}',url],stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True)
        parts=proc.stdout.strip().split('\t')
        if proc.returncode==0 and parts and parts[0]=='200' and dest.exists():
            size=dest.stat().st_size
            total_bytes+=size; resolved+=1
            largest.append({'src_sha256':hashlib.sha256(url.encode()).hexdigest(),'bytes':size,'same_origin':same,'mime':(parts[1] if len(parts)>1 else '')[:50]})
        else:
            failed+=1
    largest=sorted(largest,key=lambda x:x['bytes'],reverse=True)[:5]
    return {
      **parse_metrics(name),
      'image_tag_count':len(imgs),
      'unique_image_resource_count':len(images),
      'image_lazy_count':lazy,
      'image_explicit_eager_count':eager,
      'image_decoding_async_count':decoding_async,
      'image_fetchpriority_high_count':fetch_high,
      'same_origin_image_resource_count':same_origin,
      'external_image_resource_count':external,
      'image_resources_resolved_count':resolved,
      'image_resources_failed_count':failed,
      'image_bytes_total':total_bytes,
      'largest_images':largest,
      'script_tag_count':len(scripts),
      'head_script_tag_count':len(head_scripts),
      'head_external_script_without_async_or_defer_count':len(blocking),
      'head_external_script_hashes':[hashlib.sha256(urllib.parse.urljoin(canonical,u).encode()).hexdigest() for u in blocking],
      'stylesheet_count':len(styles)
    }

pages=['home','category7','article91','platform19','mobile_home']
payload={
  'task':'seo_performance_resource_audit_v1',
  'audit_status':'COMPLETE',
  'pages':{p:resource_metrics(p) for p in pages},
  'raw_urls_disclosed':False,
  'secrets_disclosed':False,
  'blocking_item':'NONE'
}
with out.open('w',encoding='utf-8') as f:
    json.dump(payload,f,ensure_ascii=False,indent=2,sort_keys=True)
    f.write('\n')
PY

echo "SEO_PERFORMANCE_RESOURCE_AUDIT_V1=COMPLETE"
