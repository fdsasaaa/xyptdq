#!/bin/bash
# Rollback-gated rename of tzjq display label from 投注机巧 to 投注技巧.
set -euo pipefail
umask 077
RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"; REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"; WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"; CANONICAL="https://www.laocaimi.org"; PHASE="init"; DEPLOY="NO"; ROLLBACK="NO"; RENDER_VERIFIED="NO"; ERROR_CLASS="NONE"; BLOCKING_ITEM="NONE"
[ -n "$RESULT_FILE" ] || exit 2; [ -d "$REPO/.git" ] || exit 3; [ -f "$WEBROOT/config/database.php" ] || exit 4
TMP="$(mktemp -d /tmp/xyptdq-tzjq-rename.XXXXXX)"; trap 'rm -rf "$TMP"' EXIT
write(){ python3 - "$RESULT_FILE" "$1" "$PHASE" "$DEPLOY" "$ROLLBACK" "$RENDER_VERIFIED" "$ERROR_CLASS" "$BLOCKING_ITEM" <<'PY'
import json,sys
out,status,phase,deploy,rollback,render,error,blocker=sys.argv[1:]; p={"task":"rename_tzjq_category_v1","deployment_status":status,"phase":phase,"deploy":deploy,"rollback":rollback,"render_verified":render,"deploy_error_class":error,"blocking_item":blocker,"article_publishing_attempted":False,"secrets_disclosed":False}
with open(out,'w',encoding='utf-8') as f: json.dump(p,f,ensure_ascii=False,indent=2,sort_keys=True); f.write('\n')
PY
}
restore(){ set +e; php -r '$db=[];require $argv[1];$c=$db["default"];$pdo=new PDO("mysql:host=".$c["hostname"].";dbname=".$c["database"].";charset=utf8mb4",$c["username"],$c["password"],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);$s=$pdo->prepare("UPDATE dr_1_share_category SET name=\"投注机巧\" WHERE id=3 AND dirname=\"tzjq\" AND mid=\"news\" AND name=\"投注技巧\"");$s->execute();' "$WEBROOT/config/database.php" >/dev/null 2>&1 && ROLLBACK="YES"; set -e; }
block(){ BLOCKING_ITEM="$1"; if [ "$DEPLOY" = "PASS" ]; then restore; fi; write BLOCKED; exit 1; }
on_err(){ rc=$?; trap - ERR; ERROR_CLASS="unhandled_runtime_error"; BLOCKING_ITEM="phase_${PHASE}_exit_${rc}"; if [ "$DEPLOY" = "PASS" ]; then restore; fi; write BLOCKED || true; exit "$rc"; }; trap on_err ERR
extract_h1(){ python3 - "$1" <<'PY'
import html,re,sys
s=open(sys.argv[1],encoding='utf-8',errors='ignore').read(); m=re.search(r'<h1\b[^>]*>(.*?)</h1\s*>',s,re.I|re.S); print(re.sub(r'\s+',' ',html.unescape(re.sub(r'<[^>]+>',' ',m.group(1)))).strip() if m else '')
PY
}
PHASE="repo_sync"; cd "$REPO"; git fetch --prune origin >/dev/null 2>&1; git checkout main >/dev/null 2>&1; git reset --hard origin/main >/dev/null 2>&1
PHASE="precondition"
php -r '$db=[];require $argv[1];$c=$db["default"];$pdo=new PDO("mysql:host=".$c["hostname"].";dbname=".$c["database"].";charset=utf8mb4",$c["username"],$c["password"],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC]);$r=$pdo->query("SELECT id,name,dirname,mid,disabled,`show` AS show_flag FROM dr_1_share_category WHERE id=3 LIMIT 1")->fetch();if(!$r||$r["name"]!=="投注机巧"||$r["dirname"]!=="tzjq"||$r["mid"]!=="news"||(int)$r["disabled"]!==0||(int)$r["show_flag"]!==1){exit(7);}' "$WEBROOT/config/database.php" || { ERROR_CLASS="precondition_mismatch"; block precondition_mismatch; }
PHASE="baseline"; code=$(curl -skL --max-time 25 -o "$TMP/before.html" -w '%{http_code}' "$CANONICAL/index.php?c=category&dir=tzjq" || true); [ "$code" = 200 ] || { ERROR_CLASS="baseline_http_error"; block baseline_http_error; }
PHASE="update"; php -r '$db=[];require $argv[1];$c=$db["default"];$pdo=new PDO("mysql:host=".$c["hostname"].";dbname=".$c["database"].";charset=utf8mb4",$c["username"],$c["password"],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);$s=$pdo->prepare("UPDATE dr_1_share_category SET name=\"投注技巧\" WHERE id=3 AND dirname=\"tzjq\" AND mid=\"news\" AND name=\"投注机巧\" AND disabled=0 AND `show`=1");$s->execute();if($s->rowCount()!==1){exit(8);}' "$WEBROOT/config/database.php" || { ERROR_CLASS="category_update_failed"; block category_update_failed; }; DEPLOY="PASS"
PHASE="verify_db"; php -r '$db=[];require $argv[1];$c=$db["default"];$pdo=new PDO("mysql:host=".$c["hostname"].";dbname=".$c["database"].";charset=utf8mb4",$c["username"],$c["password"],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);$s=$pdo->query("SELECT name FROM dr_1_share_category WHERE id=3 AND dirname=\"tzjq\" AND mid=\"news\" LIMIT 1");if($s->fetchColumn()!=="投注技巧"){exit(9);}' "$WEBROOT/config/database.php" || { ERROR_CLASS="db_verify_failed"; block db_verify_failed; }
PHASE="verify_render"; code=$(curl -skL --max-time 25 -o "$TMP/after.html" -w '%{http_code}' "$CANONICAL/index.php?c=category&dir=tzjq&_seo_label_check=$(date +%s)" || true); [ "$code" = 200 ] || { ERROR_CLASS="render_http_error"; block render_http_error; }; h1="$(extract_h1 "$TMP/after.html")"; printf '%s' "$h1" | grep -Fq "投注技巧" || { ERROR_CLASS="render_name_not_updated"; block render_name_not_updated; }; RENDER_VERIFIED="PASS"
PHASE="final"; trap - ERR; write PASS; echo "RENAME_TZJQ_CATEGORY_V1=PASS"
