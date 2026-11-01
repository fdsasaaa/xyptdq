#!/bin/bash
# Read-only; the only write is the bridge's sanitized result file.
set -euo pipefail
umask 077
WEBROOT="${XYPTDQ_WEBROOT:-/www/wwwroot/59.110.217.6}"
export WEBROOT
python3 - <<'PY'
import configparser, json, os, pathlib, shutil, subprocess

def run(args):
    try:
        p = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                           timeout=90, universal_newlines=True)
        return p.stdout.strip() if p.returncode == 0 else None
    except (OSError, subprocess.TimeoutExpired):
        return None

web = pathlib.Path(os.environ['WEBROOT'])
paths = {
    'webroot': web, 'content_state': pathlib.Path('/var/lib/xyptdq-content'),
    'publisher_state': pathlib.Path('/var/lib/xyptdq-publisher'),
    'canonical_repo': pathlib.Path('/opt/xyptdq-repo'),
    'nginx_config': pathlib.Path('/etc/nginx'),
}
sizes = {}
for key, path in paths.items():
    value = run(['du', '-sb', str(path)]) if path.exists() else None
    sizes[key] = {'exists': path.exists(), 'bytes': int(value.split()[0]) if value else None}
configs = [pathlib.Path('/etc/xyptdq-backup/rclone.conf'),
           pathlib.Path('/root/.config/rclone/rclone.conf')]
onedrive_configured = False
for path in configs:
    if path.is_file():
        c = configparser.ConfigParser(interpolation=None)
        try:
            c.read(str(path))
            onedrive_configured |= any(c.get(s, 'type', fallback='') == 'onedrive' for s in c.sections())
        except configparser.Error:
            pass
result = {
    'task': 'backup_readiness_probe_v1', 'read_only': True,
    'tools': {x: shutil.which(x) is not None for x in
              ['restic', 'rclone', 'php', 'mysqldump', 'mysql', 'tar', 'rsync', 'systemctl']},
    'paths': sizes,
    'essential_cms_files': {x: (web/x).is_file() for x in
                            ['index.php', 'config/database.php', 'cache/frame.lock',
                             'cache/install.lock', 'cache/config/system.php']},
    'onedrive_configuration_present': onedrive_configured,
    'backup_configuration_present': pathlib.Path('/etc/xyptdq-backup/config.json').is_file(),
    'backup_timer_active': run(['systemctl', 'is-active', 'xyptdq-backup.timer']) == 'active',
    'disk_free_bytes': shutil.disk_usage(str(web)).free,
    'timezone': run(['timedatectl', 'show', '-p', 'Timezone', '--value']),
    'production_write_performed': False,
}
with open(os.environ['XYPTDQ_AGENT_RESULT_FILE'], 'w') as f:
    json.dump(result, f, indent=2, sort_keys=True)
PY
