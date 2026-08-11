#!/bin/bash
# Wrapper for deploy.sh that safely restores the versioned framework frame.lock
# into the runtime cache path before the canonical rsync, which intentionally
# excludes runtime cache contents.
set -euo pipefail

GIT_REF="${1:-main}"
REPO_DIR="${XYPTDQ_REPO_DIR:-/opt/xyptdq-repo}"
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
EXPECTED_FRAME_LOCK_HEX="436f646549676e697465723732"

[ -d "$REPO_DIR/.git" ] || { echo 'ERROR: Git working copy not found' >&2; exit 1; }
[ -d "$WEBROOT" ] || { echo 'ERROR: webroot not found' >&2; exit 1; }

git -C "$REPO_DIR" fetch --prune origin
TARGET_SHA=$(git -C "$REPO_DIR" rev-parse "$GIT_REF^{commit}")
TMP=$(mktemp -d /tmp/xyptdq-safe-deploy.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# The recovered historical release proves the framework marker belongs at
# cache/frame.lock and must be exactly 13 bytes: CodeIgniter72, no newline.
git -C "$REPO_DIR" show "$TARGET_SHA:site/cache/frame.lock" > "$TMP/frame.lock" || {
    echo 'ERROR: target ref does not contain site/cache/frame.lock' >&2
    exit 2
}
HEX=$(od -An -tx1 -v "$TMP/frame.lock" | tr -d ' \n')
[ "$HEX" = "$EXPECTED_FRAME_LOCK_HEX" ] || {
    echo 'ERROR: target frame.lock is not exact CodeIgniter72' >&2
    exit 3
}

mkdir -p "$WEBROOT/cache"
if [ -e "$WEBROOT/cache/frame.lock" ]; then
    PROD_HEX=$(od -An -tx1 -v "$WEBROOT/cache/frame.lock" | tr -d ' \n')
    [ "$PROD_HEX" = "$EXPECTED_FRAME_LOCK_HEX" ] || {
        echo 'ERROR: existing production cache/frame.lock has unexpected bytes; refusing overwrite' >&2
        exit 4
    }
    echo 'FRAME_LOCK_RUNTIME: ALREADY_VALID'
else
    install -o www-data -g www-data -m 0644 "$TMP/frame.lock" "$WEBROOT/cache/frame.lock"
    echo 'FRAME_LOCK_RUNTIME: RESTORED'
fi

# Execute the deploy script from the exact target ref rather than trusting the
# mutable working tree copy.
git -C "$REPO_DIR" show "$TARGET_SHA:scripts/deploy.sh" > "$TMP/deploy.sh"
chmod 700 "$TMP/deploy.sh"
XYPTDQ_REPO_DIR="$REPO_DIR" XYPTDQ_WEBROOT="$WEBROOT" bash "$TMP/deploy.sh" "$TARGET_SHA"
