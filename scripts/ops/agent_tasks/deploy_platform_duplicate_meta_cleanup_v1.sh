#!/bin/bash
# Rollback-gated cleanup for the known duplicated platform meta-description placeholder.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
CANONICAL="https://www.laocaimi.org"
EXPECTED_DUP_SHA="dbb8e77773b4bf902811040fe65903fa87692b3345a3ba0ab966518b539eb716"
EXPECTED_COUNT=20
EXPECTED_FRAME_LOCK_HEX="436f646549676e697465723732"
AFFECTED_IDS="50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66 67 82 83"

PHASE="init"
DEPLOY="NO"
ROLLBACK="NO"
DISCOVERED_COLUMN=""
MATCHED_COUNT=0
PC_UNIQUE=0
MOBILE_UNIQUE=0
PC_WITH_TITLE=0
MOBILE_WITH_TITLE=0
ARTICLE_UNCHANGED="NO"
FRAMEWORK_OK="NO"
ERROR_CLASS="NONE"
BLOCKING_ITEM="NONE"

[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3
[ -f "$WEBROOT/config/database.php" ] || exit 4

TMP="$(mktemp -d /tmp/xyptdq-platform-meta-cleanup.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

write_payload(){
  local status="$1"
  python3 - "$RESULT_FILE" "$status" "$PHASE" "$DEPLOY" "$ROLLBACK" "$DISCOVERED_COLUMN" \
    "$MATCHED_COUNT" "$PC_UNIQUE" "$MOBILE_UNIQUE" "$PC_WITH_TITLE" "$MOBILE_WITH_TITLE" \
    "$ARTICLE_UNCHANGED" "$FRAMEWORK_OK" "$ERROR_CLASS" "$BLOCKING_ITEM" <<'PY'
import json,sys
(out,status,phase,deploy,rollback,column,matched,pcu,mu,pct,mt,article,framework,error_class,blocker)=sys.argv[1:]
payload={
  "task":"deploy_platform_duplicate_meta_cleanup_v1",
  "deployment_status":status,
  "phase":phase,
  "deploy":deploy,
  "rollback":rollback,
  "discovered_meta_column":column,
  "matched_affected_page_count":int(matched),
  "pc_unique_description_count":int(pcu),
  "mobile_unique_description_count":int(mu),
  "pc_descriptions_containing_platform_title":int(pct),
  "mobile_descriptions_containing_platform_title":int(mt),
  "article91_explicit_description_unchanged":article,
  "framework_integrity":framework,
  "deploy_error_class":error_class,
  "blocking_item":blocker,
  "article_publishing_attempted":False,
  "secrets_disclosed":False
}
with open(out,"w",encoding="utf-8") as f:
    json.dump(payload,f,ensure_ascii=False,indent=2,sort_keys=True); f.write("\n")
PY
}

restore_snapshot(){
  set +e
  if [ -s "$TMP/snapshot.json" ] && [ -n "$DISCOVERED_COLUMN" ]; then
    php -r '
$db=[]; require $argv[1]; $col=$argv[2]; $snap=json_decode(file_get_contents($argv[3]),true);
if(!preg_match("/^[A-Za-z0-9_]+$/",$col) || !is_array($snap)){exit(2);}
$c=$db["default"]??[];
$pdo=new PDO("mysql:host=".$c["hostname"].";dbname=".$c["database"].";charset=utf8mb4",$c["username"],$c["password"],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);
$pdo->beginTransaction();
$sql="UPDATE dr_1_xm SET `".$col."`=:v WHERE id=:id";
$st=$pdo->prepare($sql);
foreach($snap as $r){$st->execute([":v"=>(string)$r["value"],":id"=>(int)$r["id"]]);}
$pdo->commit();
' "$WEBROOT/config/database.php" "$DISCOVERED_COLUMN" "$TMP/snapshot.json" >/dev/null 2>&1
    if [ $? -eq 0 ]; then ROLLBACK="YES"; fi
  fi
  set -e
}

block(){
  BLOCKING_ITEM="$1"
  if [ "$DEPLOY" = "PASS" ]; then restore_snapshot; fi
  write_payload BLOCKED
  echo "[platform-meta-cleanup] BLOCKED: $BLOCKING_ITEM class=$ERROR_CLASS" >&2
  exit 1
}

extract_desc(){
  python3 - "$1" <<'PY'
import html,re,sys
s=open(sys.argv[1],encoding='utf-8',errors='ignore').read()
for tag in re.findall(r'<meta\b[^>]*>',s,re.I|re.S):
    n=re.search(r'\bname\s*=\s*["\']([^"\']*)["\']',tag,re.I|re.S)
    if not n or html.unescape(n.group(1)).strip().lower()!='description':
        continue
    c=re.search(r'\bcontent\s*=\s*["\']([^"\']*)["\']',tag,re.I|re.S)
    print(html.unescape(c.group(1)).strip() if c else '')
    break
PY
}

PHASE="repo_sync"
cd "$REPO"
git fetch --prune origin >/dev/null 2>&1
git checkout main >/dev/null 2>&1
git reset --hard origin/main >/dev/null 2>&1

PHASE="discover_meta_column"
php -r '
$db=[]; require $argv[1];
$ids=array_map("intval",preg_split("/\s+/",trim($argv[2])));
$expected=$argv[3];
$c=$db["default"]??[];
$pdo=new PDO("mysql:host=".$c["hostname"].";dbname=".$c["database"].";charset=utf8mb4",$c["username"],$c["password"],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC]);
$cols=$pdo->query("SHOW COLUMNS FROM dr_1_xm")->fetchAll();
$text=[];
foreach($cols as $r){
  $name=(string)$r["Field"]; $type=strtolower((string)$r["Type"]);
  if(preg_match("/(char|text)/",$type) && preg_match("/^[A-Za-z0-9_]+$/",$name)){$text[]=$name;}
}
$ph=implode(",",array_fill(0,count($ids),"?"));
$matches=[];
foreach($text as $col){
  $st=$pdo->prepare("SELECT id,`".$col."` AS v FROM dr_1_xm WHERE id IN ($ph) ORDER BY id");
  $st->execute($ids); $rows=$st->fetchAll();
  if(count($rows)!==count($ids)){continue;}
  $ok=true;
  foreach($rows as $r){
    $v=trim((string)($r["v"]??""));
    if(hash("sha256",$v)!==$expected){$ok=false; break;}
  }
  if($ok){$matches[]=$col;}
}
echo json_encode(["matches"=>$matches],JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
' "$WEBROOT/config/database.php" "$AFFECTED_IDS" "$EXPECTED_DUP_SHA" > "$TMP/discovery.json"

DISCOVERED_COLUMN="$(python3 - "$TMP/discovery.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1],encoding='utf-8'))
m=x.get('matches') or []
print(m[0] if len(m)==1 else '')
PY
)"
[ -n "$DISCOVERED_COLUMN" ] || { ERROR_CLASS="meta_column_not_uniquely_identified"; block meta_column_not_uniquely_identified; }

PHASE="inventory_and_snapshot"
php -r '
$db=[]; require $argv[1]; $col=$argv[2]; $ids=array_map("intval",preg_split("/\s+/",trim($argv[3])));
if(!preg_match("/^[A-Za-z0-9_]+$/",$col)){exit(2);}
$c=$db["default"]??[];
$pdo=new PDO("mysql:host=".$c["hostname"].";dbname=".$c["database"].";charset=utf8mb4",$c["username"],$c["password"],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC]);
$ph=implode(",",array_fill(0,count($ids),"?"));
$st=$pdo->prepare("SELECT id,title,`".$col."` AS value FROM dr_1_xm WHERE status=9 AND id IN ($ph) ORDER BY id");
$st->execute($ids); $rows=$st->fetchAll();
echo json_encode($rows,JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
' "$WEBROOT/config/database.php" "$DISCOVERED_COLUMN" "$AFFECTED_IDS" > "$TMP/snapshot.json"

MATCHED_COUNT="$(python3 - "$TMP/snapshot.json" "$EXPECTED_DUP_SHA" <<'PY'
import hashlib,json,sys
rows=json.load(open(sys.argv[1],encoding='utf-8')); expected=sys.argv[2]
ok=[r for r in rows if hashlib.sha256(str(r.get('value','')).strip().encode()).hexdigest()==expected and str(r.get('title','')).strip()]
titles=[str(r.get('title','')).strip() for r in rows]
print(len(ok) if len(set(titles))==len(titles) else -1)
PY
)"
[ "$MATCHED_COUNT" -eq "$EXPECTED_COUNT" ] || { ERROR_CLASS="affected_inventory_mismatch"; block affected_inventory_mismatch; }

PHASE="pre_render_verify"
: > "$TMP/before.desc"
while read -r pid; do
  code=$(curl -skL --max-time 25 -o "$TMP/before-$pid.html" -w '%{http_code}' "$CANONICAL/index.php?c=show&id=$pid")
  [ "$code" = 200 ] || { ERROR_CLASS="affected_page_http_not_200_before"; block affected_page_http_not_200_before; }
  d="$(extract_desc "$TMP/before-$pid.html")"
  [ "$(printf '%s' "$d" | sha256sum | awk '{print $1}')" = "$EXPECTED_DUP_SHA" ] || { ERROR_CLASS="rendered_duplicate_hash_changed"; block rendered_duplicate_hash_changed; }
  printf '%s\n' "$d" >> "$TMP/before.desc"
done < <(printf '%s\n' $AFFECTED_IDS)

curl -skL --max-time 25 -o "$TMP/article.before.html" "$CANONICAL/index.php?c=show&id=91"
ARTICLE_BEFORE="$(extract_desc "$TMP/article.before.html")"
[ -n "$ARTICLE_BEFORE" ] || { ERROR_CLASS="article91_baseline_description_missing"; block article91_baseline_description_missing; }

PHASE="database_update"
php -r '
$db=[]; require $argv[1]; $col=$argv[2]; $rows=json_decode(file_get_contents($argv[3]),true);
if(!preg_match("/^[A-Za-z0-9_]+$/",$col) || !is_array($rows)){exit(2);}
$c=$db["default"]??[];
$pdo=new PDO("mysql:host=".$c["hostname"].";dbname=".$c["database"].";charset=utf8mb4",$c["username"],$c["password"],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);
$pdo->beginTransaction();
$sql="UPDATE dr_1_xm SET `".$col."`=:v WHERE id=:id AND status=9";
$st=$pdo->prepare($sql);
foreach($rows as $r){
  $title=trim(strip_tags((string)$r["title"]));
  $desc=$title."平台资料：整理平台访问、规则、使用说明与风险提示，仅作信息导航，不构成信誉、安全或收益保证。";
  $st->execute([":v"=>$desc,":id"=>(int)$r["id"]]);
  if($st->rowCount()!==1){$pdo->rollBack(); exit(3);}
}
$pdo->commit();
' "$WEBROOT/config/database.php" "$DISCOVERED_COLUMN" "$TMP/snapshot.json" || { ERROR_CLASS="database_update_failed"; block database_update_failed; }
DEPLOY="PASS"

PHASE="post_render_verify"
MOBILE_UA='Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 Chrome/134 Mobile Safari/537.36'
: > "$TMP/pc.desc"
: > "$TMP/mobile.desc"
python3 - "$TMP/snapshot.json" <<'PY' > "$TMP/platform.tsv"
import json,sys
for r in json.load(open(sys.argv[1],encoding='utf-8')):
    print(f"{int(r['id'])}\t{str(r['title']).replace(chr(9),' ').strip()}")
PY
while IFS=$'\t' read -r pid ptitle; do
  pc_code=$(curl -skL --max-time 25 -o "$TMP/pc-$pid.html" -w '%{http_code}' "$CANONICAL/index.php?c=show&id=$pid")
  mo_code=$(curl -skL --max-time 25 -A "$MOBILE_UA" -o "$TMP/mo-$pid.html" -w '%{http_code}' "$CANONICAL/index.php?c=show&id=$pid")
  [ "$pc_code" = 200 ] || { ERROR_CLASS="platform_pc_http_not_200"; block platform_pc_http_not_200; }
  [ "$mo_code" = 200 ] || { ERROR_CLASS="platform_mobile_http_not_200"; block platform_mobile_http_not_200; }
  pc_desc="$(extract_desc "$TMP/pc-$pid.html")"
  mo_desc="$(extract_desc "$TMP/mo-$pid.html")"
  [ -n "$pc_desc" ] && [ -n "$mo_desc" ] || { ERROR_CLASS="platform_description_missing"; block platform_description_missing; }
  [ "$(printf '%s' "$pc_desc" | sha256sum | awk '{print $1}')" != "$EXPECTED_DUP_SHA" ] || { ERROR_CLASS="pc_duplicate_placeholder_persisted"; block pc_duplicate_placeholder_persisted; }
  [ "$(printf '%s' "$mo_desc" | sha256sum | awk '{print $1}')" != "$EXPECTED_DUP_SHA" ] || { ERROR_CLASS="mobile_duplicate_placeholder_persisted"; block mobile_duplicate_placeholder_persisted; }
  printf '%s\n' "$pc_desc" >> "$TMP/pc.desc"
  printf '%s\n' "$mo_desc" >> "$TMP/mobile.desc"
  if printf '%s' "$pc_desc" | grep -Fq "$ptitle"; then PC_WITH_TITLE=$((PC_WITH_TITLE+1)); fi
  if printf '%s' "$mo_desc" | grep -Fq "$ptitle"; then MOBILE_WITH_TITLE=$((MOBILE_WITH_TITLE+1)); fi
done < "$TMP/platform.tsv"

PC_UNIQUE=$(sort -u "$TMP/pc.desc" | wc -l | tr -d ' ')
MOBILE_UNIQUE=$(sort -u "$TMP/mobile.desc" | wc -l | tr -d ' ')
[ "$PC_UNIQUE" -eq "$EXPECTED_COUNT" ] || { ERROR_CLASS="pc_descriptions_not_unique"; block pc_descriptions_not_unique; }
[ "$MOBILE_UNIQUE" -eq "$EXPECTED_COUNT" ] || { ERROR_CLASS="mobile_descriptions_not_unique"; block mobile_descriptions_not_unique; }
[ "$PC_WITH_TITLE" -eq "$EXPECTED_COUNT" ] || { ERROR_CLASS="pc_description_missing_title"; block pc_description_missing_title; }
[ "$MOBILE_WITH_TITLE" -eq "$EXPECTED_COUNT" ] || { ERROR_CLASS="mobile_description_missing_title"; block mobile_description_missing_title; }

curl -skL --max-time 25 -o "$TMP/article.after.html" "$CANONICAL/index.php?c=show&id=91"
ARTICLE_AFTER="$(extract_desc "$TMP/article.after.html")"
[ "$ARTICLE_AFTER" = "$ARTICLE_BEFORE" ] || { ERROR_CLASS="explicit_article_description_changed"; block explicit_article_description_changed; }
ARTICLE_UNCHANGED="PASS"

PHASE="framework_verify"
if [ -f "$WEBROOT/dayrui/CodeIgniter72/System/Cache/CacheFactory.php" ] \
   && [ -f "$WEBROOT/cache/frame.lock" ] \
   && [ "$(od -An -tx1 -v "$WEBROOT/cache/frame.lock" | tr -d ' \n')" = "$EXPECTED_FRAME_LOCK_HEX" ]; then
  FRAMEWORK_OK="PASS"
else
  ERROR_CLASS="framework_integrity_failed"; block framework_integrity_failed
fi

PHASE="final"
ERROR_CLASS="NONE"
BLOCKING_ITEM="NONE"
write_payload PASS
echo "PLATFORM_DUPLICATE_META_CLEANUP_V1=PASS count=$MATCHED_COUNT"
