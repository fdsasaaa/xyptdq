#!/bin/bash
# Read-only diagnostic for category 7 metadata and runtime cache visibility.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
TMP_CATEGORY=$(mktemp /tmp/xyptdq-category7.XXXXXX.json)
cleanup() { rm -f "$TMP_CATEGORY"; }
trap cleanup EXIT

[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3
cd "$REPO"
git fetch --prune origin
git checkout main >/dev/null 2>&1
git reset --hard origin/main >/dev/null

php scripts/content/category_probe.php --output="$TMP_CATEGORY" >/dev/null

DB_ROWS=$(php -r '
$db=[]; require $argv[1]; $c=$db["default"]??[];
$pdo=new PDO("mysql:host=".$c["hostname"].";dbname=".$c["database"].";charset=utf8mb4",$c["username"],$c["password"],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_EMULATE_PREPARES=>false]);
$s=$pdo->query("SELECT id,catid,status,url,tableid FROM dr_1_news WHERE id IN (47,84,88) ORDER BY id");
echo json_encode($s->fetchAll(PDO::FETCH_ASSOC),JSON_UNESCAPED_SLASHES|JSON_UNESCAPED_UNICODE);
' "$WEBROOT/config/database.php")

CACHE_EXISTS=false
CACHE_FILES=0
CACHE_SEO_MENTIONS=0
CACHE_CAT7_MENTIONS=0
if [ -d "$WEBROOT/cache" ]; then
  CACHE_EXISTS=true
  CACHE_FILES=$(find "$WEBROOT/cache" -type f 2>/dev/null | wc -l | tr -d ' ')
  CACHE_SEO_MENTIONS=$(grep -RIl --binary-files=without-match -- 'seo-articles' "$WEBROOT/cache" 2>/dev/null | wc -l | tr -d ' ')
  CACHE_CAT7_MENTIONS=$(grep -RIl --binary-files=without-match -E '(^|[^0-9])7([^0-9]|$)' "$WEBROOT/cache" 2>/dev/null | wc -l | tr -d ' ')
fi

python3 - "$RESULT_FILE" "$TMP_CATEGORY" "$DB_ROWS" "$CACHE_EXISTS" "$CACHE_FILES" "$CACHE_SEO_MENTIONS" "$CACHE_CAT7_MENTIONS" <<'PY'
import json, sys
out, category_path, db_rows, cache_exists, cache_files, seo_mentions, cat7_mentions = sys.argv[1:]
with open(category_path, 'r', encoding='utf-8') as fh:
    probe = json.load(fh)
selected = {}
for row in probe.get('categories', []):
    cid = int(row.get('id', 0))
    if cid in (2, 7):
        selected[str(cid)] = {
            k: row.get(k) for k in (
                'id','pid','name','dirname','disabled','show','displayorder','mid',
                'module','module_name','_source_table','_source_model'
            ) if k in row
        }
payload = {
    'task': 'category7_runtime_diagnose',
    'diagnostic': 'PASS',
    'categories': selected,
    'article_rows': json.loads(db_rows),
    'category_sources': probe.get('sources', []),
    'runtime_cache': {
        'exists': cache_exists == 'true',
        'file_count': int(cache_files),
        'seo_articles_mention_files': int(seo_mentions),
        'category7_pattern_mention_files': int(cat7_mentions),
    },
    'secrets_disclosed': False,
}
with open(out, 'w', encoding='utf-8') as fh:
    json.dump(payload, fh, ensure_ascii=False, indent=2, sort_keys=True)
    fh.write('\n')
PY

echo "CATEGORY7_RUNTIME_DIAGNOSE=PASS"
