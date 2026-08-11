#!/bin/bash
# Rollback-gated retirement of the verified empty gdrz news category.
set -euo pipefail
umask 077
RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"; REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"; WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"; PHASE="init"; DEPLOY="NO"; ROLLBACK="NO"; ERROR_CLASS="NONE"; BLOCKING_ITEM="NONE"
[ -n "$RESULT_FILE" ] || exit 2; [ -d "$REPO/.git" ] || exit 3; [ -f "$WEBROOT/config/database.php" ] || exit 4
TMP="$(mktemp -d /tmp/xyptdq-gdrz-retire.XXXXXX)"; trap 'rm -rf "$TMP"' EXIT
write(){ python3 - "$RESULT_FILE" "$1" "$PHASE" "$DEPLOY" "$ROLLBACK" "$ERROR_CLASS" "$BLOCKING_ITEM" <<'PY'
import json,sys
out,status,phase,deploy,rollback,error,blocker=sys.argv[1:]; p={"task":"retire_empty_gdrz_category_v1","deployment_status":status,"phase":phase,"deploy":deploy,"rollback":rollback,"deploy_error_class":error,"blocking_item":blocker,"article_publishing_attempted":False,"secrets_disclosed":False}
with open(out,'w',encoding='utf-8') as f: json.dump(p,f,ensure_ascii=False,indent=2,sort_keys=True); f.write('\n')
PY
}
restore(){ set +e; if [ -s "$TMP/before.json" ]; then php -r '$db=[];require $argv[1];$r=json_decode(file_get_contents($argv[2]),true);$c=$db["default"];$pdo=new PDO("mysql:host=".$c["hostname"].";dbname=".$c["database"].";charset=utf8mb4",$c["username"],$c["password"],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);$s=$pdo->prepare("UPDATE dr_1_share_category SET disabled=?,`show`=? WHERE id=5 AND dirname=\"gdrz\"");$s->execute([(int)$r["disabled"],(int)$r["show_flag"]]);' "$WEBROOT/config/database.php" "$TMP/before.json" >/dev/null 2>&1 && ROLLBACK="YES"; fi; set -e; }
block(){ BLOCKING_ITEM="$1"; if [ "$DEPLOY" = "PASS" ]; then restore; fi; write BLOCKED; exit 1; }
on_err(){ rc=$?; trap - ERR; ERROR_CLASS="unhandled_runtime_error"; BLOCKING_ITEM="phase_${PHASE}_exit_${rc}"; if [ "$DEPLOY" = "PASS" ]; then restore; fi; write BLOCKED || true; exit "$rc"; }; trap on_err ERR
PHASE="repo_sync"; cd "$REPO"; git fetch --prune origin >/dev/null 2>&1; git checkout main >/dev/null 2>&1; git reset --hard origin/main >/dev/null 2>&1
PHASE="precondition"
php -r '$db=[];require $argv[1];$c=$db["default"];$pdo=new PDO("mysql:host=".$c["hostname"].";dbname=".$c["database"].";charset=utf8mb4",$c["username"],$c["password"],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC]);$r=$pdo->query("SELECT id,name,dirname,mid,disabled,`show` AS show_flag FROM dr_1_share_category WHERE id=5 LIMIT 1")->fetch();$n=(int)$pdo->query("SELECT COUNT(*) FROM dr_1_news WHERE catid=5")->fetchColumn();if(!$r||$r["name"]!=="跟单日志"||$r["dirname"]!=="gdrz"||$r["mid"]!=="news"||(int)$r["disabled"]!==0||(int)$r["show_flag"]!==1||$n!==0){exit(7);}echo json_encode($r,JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);' "$WEBROOT/config/database.php" > "$TMP/before.json" || { ERROR_CLASS="precondition_mismatch"; block precondition_mismatch; }
PHASE="update"
php -r '$db=[];require $argv[1];$c=$db["default"];$pdo=new PDO("mysql:host=".$c["hostname"].";dbname=".$c["database"].";charset=utf8mb4",$c["username"],$c["password"],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);$s=$pdo->prepare("UPDATE dr_1_share_category SET disabled=1,`show`=0 WHERE id=5 AND dirname=\"gdrz\" AND name=\"跟单日志\" AND mid=\"news\" AND disabled=0 AND `show`=1");$s->execute();if($s->rowCount()!==1){exit(8);}' "$WEBROOT/config/database.php" || { ERROR_CLASS="category_update_failed"; block category_update_failed; }; DEPLOY="PASS"
PHASE="verify"
php -r '$db=[];require $argv[1];$c=$db["default"];$pdo=new PDO("mysql:host=".$c["hostname"].";dbname=".$c["database"].";charset=utf8mb4",$c["username"],$c["password"],[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC]);$r=$pdo->query("SELECT disabled,`show` AS show_flag FROM dr_1_share_category WHERE id=5 AND dirname=\"gdrz\" LIMIT 1")->fetch();$n=(int)$pdo->query("SELECT COUNT(*) FROM dr_1_news WHERE catid=5")->fetchColumn();if(!$r||(int)$r["disabled"]!==1||(int)$r["show_flag"]!==0||$n!==0){exit(9);}' "$WEBROOT/config/database.php" || { ERROR_CLASS="post_verify_failed"; block post_verify_failed; }
PHASE="final"; trap - ERR; write PASS; echo "RETIRE_EMPTY_GDRZ_V1=PASS"
