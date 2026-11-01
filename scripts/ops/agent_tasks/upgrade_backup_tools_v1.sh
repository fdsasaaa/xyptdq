#!/bin/bash
# Official pinned binaries, checked against GitHub release-asset SHA-256 digests.
set -euo pipefail
umask 077
[ "$(id -u)" -eq 0 ]
[ "$(uname -m)" = x86_64 ]
WORK=$(mktemp -d /var/lib/xyptdq-backup/tools.XXXXXX)
trap 'rm -rf -- "$WORK"' EXIT
curl --fail --location --silent --show-error --retry 2 --max-time 180 \
  https://github.com/rclone/rclone/releases/download/v1.75.2/rclone-v1.75.2-linux-amd64.zip \
  --output "$WORK/rclone.zip"
curl --fail --location --silent --show-error --retry 2 --max-time 180 \
  https://github.com/restic/restic/releases/download/v0.19.1/restic_0.19.1_linux_amd64.bz2 \
  --output "$WORK/restic.bz2"
printf '%s  %s\n' \
  349ac8fba6ff65d6247043f1750cdcb518ec5d500ef91463a10d37c0ccdf3702 "$WORK/rclone.zip" \
  f415415624dcc452f2a02b8c33641791a8c6d6d3b65bbb3543fcf9a25151585c "$WORK/restic.bz2" | sha256sum --check --status
python3 - "$WORK" <<'PY'
import bz2, pathlib, sys, zipfile
p = pathlib.Path(sys.argv[1])
with zipfile.ZipFile(str(p/'rclone.zip')) as z:
    (p/'rclone').write_bytes(z.read('rclone-v1.75.2-linux-amd64/rclone'))
(p/'restic').write_bytes(bz2.decompress((p/'restic.bz2').read_bytes()))
PY
install -o root -g root -m 0755 "$WORK/rclone" /usr/local/bin/rclone
install -o root -g root -m 0755 "$WORK/restic" /usr/local/bin/restic
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
rclone version | sed -n '1p' | grep -Fx 'rclone v1.75.2'
restic version | grep -F 'restic 0.19.1 '
CONTROL="${XYPTDQ_AGENT_CONTROL_REPO:-/var/lib/xyptdq-agent/control.git}"
COMMIT="${XYPTDQ_AGENT_REQUIRED_COMMIT:?}"
for name in onedrive_backup.py install_timer.sh; do
  git --git-dir="$CONTROL" show "$COMMIT:scripts/backup/$name" > "$WORK/$name"
  install -o root -g root -m 0700 "$WORK/$name" "/usr/local/lib/xyptdq-backup/$name"
done
mkdir "$WORK/source"
printf 'xyptdq-pinned-tool-roundtrip-v1\n' > "$WORK/source/probe.txt"
restic --repo "$WORK/repository" --password-file /etc/xyptdq-backup/repository-password init
restic --repo "$WORK/repository" --password-file /etc/xyptdq-backup/repository-password backup --json "$WORK/source"
restic --repo "$WORK/repository" --password-file /etc/xyptdq-backup/repository-password restore latest --target "$WORK/restored"
cmp "$WORK/source/probe.txt" "$WORK/restored$WORK/source/probe.txt"
restic --repo "$WORK/repository" --password-file /etc/xyptdq-backup/repository-password check --read-data
python3 - <<'PY'
import json, os
with open(os.environ['XYPTDQ_AGENT_RESULT_FILE'], 'w') as f:
    json.dump({'task':'upgrade_backup_tools_v1', 'status':'PASS',
               'restic_version':'0.19.1', 'rclone_version':'1.75.2',
               'official_asset_sha256_verified':True,
               'local_encrypted_roundtrip_verified':True,
               'remote_snapshot_created':False, 'daily_timer_enabled':False}, f, indent=2)
PY
