#!/bin/bash
# Install only after Microsoft authorization, first backup and download verification.
set -euo pipefail
umask 077
[ "$(id -u)" -eq 0 ]
SOURCE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
for tool in restic rclone python3 mysqldump php tar git; do command -v "$tool" >/dev/null; done
python3 "$SOURCE/onedrive_backup.py" status >/dev/null
install -d -m 0700 /usr/local/lib/xyptdq-backup
if ! [ "$SOURCE/onedrive_backup.py" -ef /usr/local/lib/xyptdq-backup/onedrive_backup.py ]; then
  install -m 0700 "$SOURCE/onedrive_backup.py" /usr/local/lib/xyptdq-backup/onedrive_backup.py
fi
cat > /etc/systemd/system/xyptdq-backup.service <<'EOF'
[Unit]
Description=XYPTDQ encrypted OneDrive backup and download verification
Wants=network-online.target
After=network-online.target mariadb.service
StartLimitIntervalSec=2h
StartLimitBurst=3

[Service]
Type=oneshot
User=root
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
UMask=0077
Nice=10
IOSchedulingClass=idle
TimeoutStartSec=6h
Restart=on-failure
RestartSec=15m
ExecStart=/usr/bin/python3 /usr/local/lib/xyptdq-backup/onedrive_backup.py backup
StandardOutput=journal
StandardError=journal
EOF
cat > /etc/systemd/system/xyptdq-backup.timer <<'EOF'
[Unit]
Description=Daily XYPTDQ backup at 03:30 Asia/Shanghai

[Timer]
OnCalendar=*-*-* 03:30:00 Asia/Shanghai
RandomizedDelaySec=5m
Persistent=true
Unit=xyptdq-backup.service

[Install]
WantedBy=timers.target
EOF
systemd-analyze verify /etc/systemd/system/xyptdq-backup.service /etc/systemd/system/xyptdq-backup.timer
systemctl daemon-reload
systemctl enable --now xyptdq-backup.timer
systemctl is-active --quiet xyptdq-backup.timer
echo 'Daily backup timer active (Asia/Shanghai 03:30, up to five minutes jitter).'
