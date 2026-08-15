#!/bin/bash
set -u
RESULT_FILE="${XYPTDQ_AGENT_RESULT_FILE:-}"
REPO="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
[ -n "$RESULT_FILE" ] || exit 2
BASH_BIN="$(command -v bash 2>/dev/null || true)"
GIT_BIN="$(command -v git 2>/dev/null || true)"
PHP_BIN="$(command -v php 2>/dev/null || true)"
PY_BIN="$(command -v python3 2>/dev/null || true)"
TARGET1="$REPO/scripts/ops/agent_tasks/diagnose_cf50_021_sitemap_url_v2.sh"
TARGET2="$REPO/scripts/ops/agent_tasks/probe_article_repo_transport_v1.sh"
python3 - "$RESULT_FILE" "$REPO" "$BASH_BIN" "$GIT_BIN" "$PHP_BIN" "$PY_BIN" "$TARGET1" "$TARGET2" <<'PY'
import json, os, sys
out,repo,bash_bin,git_bin,php_bin,py_bin,t1,t2=sys.argv[1:]
payload={
 "task":"bridge_runtime_env_probe_v1","status":"PASS","read_only":True,
 "repo_dir":repo,"repo_exists":os.path.isdir(repo),
 "bash_bin":bash_bin or None,"git_bin":git_bin or None,"php_bin":php_bin or None,"python3_bin":py_bin or None,
 "target1_exists":os.path.isfile(t1),"target2_exists":os.path.isfile(t2),
 "target1_mode":oct(os.stat(t1).st_mode & 0o777) if os.path.isfile(t1) else None,
 "target2_mode":oct(os.stat(t2).st_mode & 0o777) if os.path.isfile(t2) else None,
 "cms_write_attempted":False,"cron_mutated":False,"queue_consumed":False
}
with open(out,"w",encoding="utf-8") as f:
 json.dump(payload,f,ensure_ascii=False,indent=2,sort_keys=True); f.write("\n")
PY
exit 0
