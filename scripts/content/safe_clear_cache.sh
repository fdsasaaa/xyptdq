#!/bin/bash
set -euo pipefail

WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
CACHE_DIR="$WEBROOT/cache"

if [ ! -d "$CACHE_DIR" ]; then
  echo "[cache] ERROR: cache directory not found: $CACHE_DIR" >&2
  exit 1
fi

for subdir in template data; do
  target="$CACHE_DIR/$subdir"
  if [ -d "$target" ]; then
    find "$target" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
    echo "[cache] cleared: $target"
  else
    echo "[cache] skip missing directory: $target"
  fi
done

# Safety invariant: never create, rewrite, or remove CMS lock/config files here.
for protected in "$CACHE_DIR/install.lock" "$CACHE_DIR/frame.lock" "$CACHE_DIR/config/system.php"; do
  if [ -e "$protected" ]; then
    echo "[cache] protected file preserved: $protected"
  fi
done

echo "[cache] OK"
