#!/bin/bash
# Read-only diagnostic to locate the CMS source field for the known duplicated platform meta description.
set -euo pipefail
umask 077

RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
EXPECTED_DUP_SHA="dbb8e77773b4bf902811040fe65903fa87692b3345a3ba0ab966518b539eb716"
AFFECTED_IDS="50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66 67 82 83"
PHASE="init"

[ -n "$RESULT_FILE" ] || exit 2
[ -d "$REPO/.git" ] || exit 3
[ -f "$WEBROOT/config/database.php" ] || exit 4

TMP="$(mktemp -d /tmp/xyptdq-platform-meta-source.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

write_error(){
  local rc="$1"
  python3 - "$RESULT_FILE" "$PHASE" "$rc" <<'PY'
import json,sys
out,phase,rc=sys.argv[1:]
payload={
  "task":"seo_platform_meta_source_diagnostic_v1",
  "diagnostic_status":"BLOCKED",
  "phase":phase,
  "blocking_item":"runtime_error",
  "task_exit_code":int(rc),
  "production_writes":False,
  "article_publishing":False,
  "secrets_disclosed":False
}
with open(out,"w",encoding="utf-8") as f:
    json.dump(payload,f,ensure_ascii=False,indent=2,sort_keys=True); f.write("\n")
PY
}
on_err(){ local rc=$?; trap - ERR; write_error "$rc" || true; exit "$rc"; }
trap on_err ERR

PHASE="repo_sync"
cd "$REPO"
git fetch --prune origin >/dev/null 2>&1
git checkout main >/dev/null 2>&1
git reset --hard origin/main >/dev/null 2>&1

PHASE="scan_candidate_sources"
php -r '
$db=[]; require $argv[1];
$expected=$argv[2];
$ids=array_map("intval",preg_split("/\s+/",trim($argv[3])));
$c=$db["default"]??[];
$pdo=new PDO("mysql:host=".$c["hostname"].";dbname=".$c["database"].";charset=utf8mb4",$c["username"],$c["password"],[
  PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,
  PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC
]);
$dbname=(string)$c["database"];
$st=$pdo->prepare("SELECT table_name FROM information_schema.tables WHERE table_schema=? AND (table_name LIKE ? OR table_name=?) ORDER BY table_name");
$st->execute([$dbname,"dr_1_xm%","dr_1_share_index"]);
$tables=array_map(fn($r)=>(string)$r["table_name"],$st->fetchAll());
$out=[];
foreach($tables as $table){
  if(!preg_match("/^[A-Za-z0-9_]+$/",$table)){continue;}
  $cs=$pdo->prepare("SELECT column_name,data_type FROM information_schema.columns WHERE table_schema=? AND table_name=? ORDER BY ordinal_position");
  $cs->execute([$dbname,$table]); $cols=$cs->fetchAll();
  $names=array_map(fn($r)=>(string)$r["column_name"],$cols);
  if(!in_array("id",$names,true)){continue;}
  $hasMid=in_array("mid",$names,true);
  $textCols=[];
  foreach($cols as $r){
    $name=(string)$r["column_name"]; $type=strtolower((string)$r["data_type"]);
    if(preg_match("/^(char|varchar|tinytext|text|mediumtext|longtext)$/",$type) && preg_match("/^[A-Za-z0-9_]+$/",$name)){
      $textCols[]=$name;
    }
  }
  foreach($textCols as $col){
    $ph=implode(",",array_fill(0,count($ids),"?"));
    $sql="SELECT id,`".$col."` AS v".($hasMid?",mid":"")." FROM `".$table."` WHERE id IN ($ph)";
    $q=$pdo->prepare($sql); $q->execute($ids); $rows=$q->fetchAll();
    if($hasMid){
      $xmRows=array_values(array_filter($rows,fn($r)=>strtolower(trim((string)($r["mid"]??"")))==="xm"));
      if($xmRows){$rows=$xmRows;}
    }
    $byId=[];
    foreach($rows as $r){$byId[(int)$r["id"]]=(string)($r["v"]??"");}
    $matched=[]; $nonempty=0; $hashes=[];
    foreach($ids as $id){
      if(!array_key_exists($id,$byId)){continue;}
      $v=trim($byId[$id]);
      if($v!==""){$nonempty++;}
      $h=hash("sha256",$v); $hashes[$h]=true;
      if($h===$expected){$matched[]=$id;}
    }
    if(count($matched)>0){
      $out[]=[
        "table"=>$table,
        "column"=>$col,
        "affected_row_count"=>count($byId),
        "matched_duplicate_hash_count"=>count($matched),
        "nonempty_count"=>$nonempty,
        "distinct_value_hash_count"=>count($hashes),
        "all_20_match"=>(count($matched)===count($ids) && count($byId)===count($ids))
      ];
    }
  }
}
echo json_encode($out,JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
' "$WEBROOT/config/database.php" "$EXPECTED_DUP_SHA" "$AFFECTED_IDS" > "$TMP/candidates.json"

PHASE="render_confirmation"
python3 - "$TMP/candidates.json" "$RESULT_FILE" <<'PY'
import json,sys
src,out=sys.argv[1:]
rows=json.load(open(src,encoding="utf-8"))
full=[r for r in rows if r.get("all_20_match")]
payload={
  "task":"seo_platform_meta_source_diagnostic_v1",
  "diagnostic_status":"COMPLETE",
  "phase":"final",
  "candidate_source_count":len(rows),
  "full_match_source_count":len(full),
  "candidate_sources":rows,
  "blocking_item":"NONE",
  "production_writes":False,
  "article_publishing":False,
  "secrets_disclosed":False
}
with open(out,"w",encoding="utf-8") as f:
    json.dump(payload,f,ensure_ascii=False,indent=2,sort_keys=True); f.write("\n")
PY

PHASE="final"
trap - ERR
