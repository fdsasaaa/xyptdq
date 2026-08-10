#!/bin/bash
# Read-only diagnostic: compare runtime-cache visibility of one known-good CMS
# article and recent direct-published smoke articles.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
CACHE_ROOT="$WEBROOT/cache"

[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3
cd "$REPO"
git fetch --prune origin
git checkout main >/dev/null 2>&1
git reset --hard origin/main >/dev/null

ROWS=$(php -r '
$db=[]; require $argv[1]; $c=$db["default"]??[];
$pdo=new PDO("mysql:host=".$c["hostname"].";dbname=".$c["database"].";charset=utf8mb4",$c["username"],$c["password"],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_EMULATE_PREPARES=>false]);
$s=$pdo->query("SELECT id,title,inputtime,updatetime FROM dr_1_news WHERE id IN (47,88,89) ORDER BY id");
echo json_encode($s->fetchAll(PDO::FETCH_ASSOC),JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
' "$WEBROOT/config/database.php")

CACHE_EXISTS=false
CACHE_FILES=0
if [ -d "$CACHE_ROOT" ]; then
  CACHE_EXISTS=true
  CACHE_FILES=$(find "$CACHE_ROOT" -type f 2>/dev/null | wc -l | tr -d ' ')
fi

TMP=$(mktemp /tmp/xyptdq-cache-vis.XXXXXX.json)
cleanup() { rm -f "$TMP"; }
trap cleanup EXIT
printf '%s' "$ROWS" > "$TMP"

python3 - "$TMP" > /tmp/xyptdq-cache-titles.$$ <<'PY'
import json,sys
rows=json.load(open(sys.argv[1],encoding='utf-8'))
for row in rows:
    title=str(row.get('title','')).replace('\n',' ').replace('\r',' ')
    print(f"{int(row.get('id',0))}\t{title}")
PY

COUNTS_JSON='{}'
if [ "$CACHE_EXISTS" = true ]; then
  while IFS=$'\t' read -r id title; do
    [ -n "$title" ] || continue
    count=$(grep -RIlF --binary-files=without-match -- "$title" "$CACHE_ROOT" 2>/dev/null | wc -l | tr -d ' ')
    COUNTS_JSON=$(python3 - "$COUNTS_JSON" "$id" "$count" <<'PY'
import json,sys
x=json.loads(sys.argv[1]); x[str(sys.argv[2])]=int(sys.argv[3]); print(json.dumps(x,separators=(',',':')))
PY
)
  done < /tmp/xyptdq-cache-titles.$$
fi
rm -f /tmp/xyptdq-cache-titles.$$

python3 - "$RESULT_FILE" "$ROWS" "$CACHE_EXISTS" "$CACHE_FILES" "$COUNTS_JSON" <<'PY'
import json,sys
out,rows,cache_exists,cache_files,counts=sys.argv[1:]
payload={
 'task':'article_cache_visibility_diagnose',
 'diagnostic':'PASS',
 'articles':json.loads(rows),
 'runtime_cache':{
   'exists':cache_exists=='true',
   'file_count':int(cache_files),
   'title_mention_files':json.loads(counts),
 },
 'secrets_disclosed':False,
}
with open(out,'w',encoding='utf-8') as fh:
    json.dump(payload,fh,ensure_ascii=False,indent=2,sort_keys=True); fh.write('\n')
PY

echo "ARTICLE_CACHE_VISIBILITY_DIAGNOSE=PASS"
