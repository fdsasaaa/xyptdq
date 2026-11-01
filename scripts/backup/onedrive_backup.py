#!/usr/bin/env python3
"""Encrypted off-server recovery snapshots. No credentials or raw output are published."""
import argparse
import contextlib
import datetime as dt
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tarfile

TAG = 'xyptdq-daily-v1'
HOST = 'xyptdq-production'
ESSENTIAL = ('index.php', 'config/database.php', 'cache/frame.lock',
             'cache/install.lock', 'cache/config/system.php')


class BackupError(Exception):
    pass


def now():
    return dt.datetime.now(dt.timezone.utc).isoformat()


def private_file(path):
    path = Path(path)
    s = path.lstat()
    if not stat.S_ISREG(s.st_mode) or s.st_uid != 0 or s.st_mode & 0o077:
        raise BackupError('configuration and key files must be root-owned regular files, mode 0600')
    return path


def atomic_json(path, data):
    path = Path(path)
    tmp = path.with_name(path.name + '.new')
    with open(str(tmp), 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2, sort_keys=True)
        f.write('\n')
    os.chmod(str(tmp), 0o600)
    os.replace(str(tmp), str(path))


def load_config(path):
    c = json.loads(private_file(path).read_text())
    if c.get('schema_version') != 1:
        raise BackupError('unsupported configuration')
    # A remote root inside a dedicated OneDrive folder; local-only repositories are rejected.
    if not re.fullmatch(r'rclone:[A-Za-z0-9_-]+:[A-Za-z0-9_./-]+', c.get('repository', '')):
        raise BackupError('a dedicated rclone remote repository is required')
    if '..' in c['repository'].split(':', 2)[2].split('/'):
        raise BackupError('unsafe repository path')
    for name in ('webroot', 'repo_dir', 'state_dir', 'password_file', 'rclone_config'):
        if not Path(c[name]).is_absolute():
            raise BackupError('absolute configuration paths are required')
    web, state = Path(c['webroot']).resolve(), Path(c['state_dir']).resolve()
    if web == state or web in state.parents or state in web.parents:
        raise BackupError('backup state and webroot must not overlap')
    if state == Path('/'):
        raise BackupError('unsafe state directory')
    private_file(c['password_file'])
    private_file(c['rclone_config'])
    if not Path(c['password_file']).read_text().strip():
        raise BackupError('encryption password is empty')
    import configparser
    remote = c['repository'].split(':', 2)[1]
    rc = configparser.ConfigParser(interpolation=None)
    rc.read(c['rclone_config'])
    if rc.get(remote, 'type', fallback='') != 'onedrive':
        raise BackupError('the configured remote must be OneDrive')
    os.environ['RESTIC_PASSWORD_FILE'] = c['password_file']
    os.environ['RCLONE_CONFIG'] = c['rclone_config']
    os.environ['RESTIC_REPOSITORY'] = c['repository']
    os.environ['RESTIC_CACHE_DIR'] = str(state / 'cache')
    return c


def run(args, output=None, input_text=None):
    # All subprocess output remains in the private systemd log; never interpolate shell code.
    result = subprocess.run([str(x) for x in args], input=input_text,
                            stdout=output if output is not None else subprocess.PIPE,
                            stderr=subprocess.PIPE, universal_newlines=True)
    if result.returncode:
        raise BackupError('command failed: ' + Path(str(args[0])).name)
    return result.stdout


def restic(*args):
    return run(['restic'] + list(args))


def archive(target, root, paths, excludes=()):
    args = ['tar', '--create', '--file', target]
    args += ['--exclude=' + x for x in excludes]
    args += ['--directory', root, '--'] + list(paths)
    # A changed file produces tar exit 1 and fails the snapshot instead of claiming completeness.
    run(args)


def verify_stage(stage):
    stage = Path(stage)
    manifest = json.loads((stage / 'manifest.json').read_text())
    if manifest.get('schema_version') != 1:
        raise BackupError('invalid recovery manifest')
    required = {'website.tar', 'database.sql', 'runtime.tar', 'system.tar', 'source.bundle',
                'environment.json', 'root-crontab.txt'}
    if set(manifest['sha256']) != required:
        raise BackupError('incomplete recovery manifest')
    for name, digest in manifest['sha256'].items():
        p = stage / name
        if not p.is_file() or p.is_symlink() or p.stat().st_size == 0:
            raise BackupError('missing recovery payload')
        if sha256(p) != digest:
            raise BackupError('recovery checksum mismatch')
    with tarfile.open(str(stage / 'website.tar'), 'r:') as tf:
        names = {x.name.lstrip('./') for x in tf.getmembers()}
        if not set(ESSENTIAL).issubset(names):
            raise BackupError('essential CMS recovery files missing')
    return manifest


def sha256(path):
    h = hashlib.sha256()
    with open(str(path), 'rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def build_stage(c):
    # Coordinate with the existing PHP/shell publisher and intake flock files.
    # Manual CMS edits remain live; this is not an atomic volume image.
    roots = [Path('/var/lib/xyptdq-content'), Path('/var/lib/xyptdq-publisher')]
    locks = set()
    for root in roots:
        if root.exists():
            locks.update(root.rglob('*.lock'))
    with contextlib.ExitStack() as stack:
        for path in sorted(locks):
            if not path.is_file() or path.is_symlink():
                raise BackupError('unsafe application lock')
            f = stack.enter_context(open(str(path), 'a'))
            try:
                fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise BackupError('publisher or intake is active; retry backup later')
        return _build_stage(c)


def _build_stage(c):
    state, web, repo = (Path(c[k]) for k in ('state_dir', 'webroot', 'repo_dir'))
    for item in ESSENTIAL:
        if not (web / item).is_file():
            raise BackupError('essential CMS file absent')
    for p in (repo, Path('/var/lib/xyptdq-content'), Path('/var/lib/xyptdq-publisher')):
        if not p.is_dir():
            raise BackupError('required source or publisher state absent')
    # Stable filenames let Restic deduplicate unchanged tar/SQL blocks across daily snapshots.
    stage = state / 'staging'
    stage.mkdir(mode=0o700, exist_ok=True)
    if stage.is_symlink():
        raise BackupError('unsafe staging directory')
    for p in stage.iterdir():
        if not p.is_file() or p.is_symlink():
            raise BackupError('unexpected staging entry')
        p.unlink()
    # Keep cache/config, cache/data and both locks. Exclude only disposable files.
    archive(stage / 'website.tar', web, ['.'],
            ('./.git', './cache/template', './cache/session', './cache/log'))
    db = run(['php', '-r', '$db=[];require $argv[1];echo $db["default"]["database"]??"";',
              web / 'config/database.php']).strip()
    if not re.fullmatch(r'[A-Za-z0-9_]+', db):
        raise BackupError('invalid CMS database identity')
    # --lock-all-tables works for both InnoDB and legacy MyISAM. The brief read lock
    # may delay writes. Credentials use local administrative socket authentication.
    with open(str(stage / 'database.sql'), 'w') as f:
        run(['mysqldump', '--lock-all-tables', '--routines', '--triggers', '--events',
             '--hex-blob', '--default-character-set=utf8mb4', db], output=f)
    archive(stage / 'runtime.tar', '/', ['var/lib/xyptdq-content',
            'var/lib/xyptdq-publisher', str(repo).lstrip('/')],
            (str(repo).lstrip('/') + '/.git',))
    system = ['etc/nginx', 'etc/php', 'etc/mysql', 'etc/cron.d', 'etc/crontab']
    for path in ('etc/letsencrypt', 'etc/systemd/system'):
        if Path('/' + path).exists():
            system.append(path)
    archive(stage / 'system.tar', '/', system)
    # Do not copy OneDrive access configuration or encryption keys into the recovery payload.
    proc = subprocess.run(['crontab', '-l'], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          universal_newlines=True)
    if proc.returncode not in (0, 1):
        raise BackupError('cannot read root cron')
    (stage / 'root-crontab.txt').write_text(proc.stdout or '# no root crontab\n')
    run(['git', '-C', repo, 'bundle', 'create', stage / 'source.bundle', 'HEAD'])
    commit = run(['git', '-C', repo, 'rev-parse', 'HEAD']).strip()
    environment = {}
    for label, args in {'php': ['php', '-v'], 'php_modules': ['php', '-m'],
                        'mysql': ['mysql', '--version'], 'nginx': ['nginx', '-v'],
                        'restic': ['restic', 'version'], 'rclone': ['rclone', 'version'],
                        'packages': ['dpkg-query', '-W'],
                        'units': ['systemctl', 'list-timers', '--all', '--no-pager']}.items():
        p = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           universal_newlines=True)
        environment[label] = p.stdout
    if Path('/etc/os-release').is_file():
        environment['os_release'] = Path('/etc/os-release').read_text()
    atomic_json(stage / 'environment.json', environment)
    payloads = sorted(p.name for p in stage.iterdir())
    manifest = {'schema_version': 1, 'created_at': now(), 'source_commit': commit,
                'database_name': db, 'webroot': str(web), 'repository_path': str(repo),
                'consistency': 'database read-locked dump; live website files, not a filesystem point-in-time image',
                'sha256': {name: sha256(stage / name) for name in payloads}}
    atomic_json(stage / 'manifest.json', manifest)
    verify_stage(stage)
    return stage


def save_status(state, outcome, **fields):
    path = Path(state) / 'status.json'
    old = json.loads(path.read_text()) if path.exists() else {}
    result = {'schema_version': 1, 'observed_at': now(), 'outcome': outcome,
              'last_success': old.get('last_success'), **fields}
    if outcome == 'PASS':
        result['last_success'] = {'finished_at': result['observed_at'],
                                  'snapshot_id': fields['snapshot_id']}
    atomic_json(path, result)
    return result


def snapshot_id(requested):
    snapshots = json.loads(restic('snapshots', '--json', '--host', HOST, '--tag', TAG))
    if not snapshots:
        raise BackupError('no verified-site snapshot exists')
    if requested == 'latest':
        return max(snapshots, key=lambda s: s['time'])['id']
    if not re.fullmatch(r'[0-9a-f]{8,64}', requested):
        raise BackupError('snapshot must be latest or an ID from the inventory')
    hits = [s['id'] for s in snapshots if s['id'].startswith(requested)]
    if len(hits) != 1:
        raise BackupError('snapshot ID absent or ambiguous')
    return hits[0]


def safe_members(archive_path):
    # For a later fresh-host import. Reject links/devices and traversal before extraction.
    with tarfile.open(str(archive_path), 'r:') as tf:
        for item in tf.getmembers():
            parts = Path(item.name).parts
            if Path(item.name).is_absolute() or '..' in parts or not (item.isfile() or item.isdir()):
                raise BackupError('archive requires manual review before import')


def restore_stage(snapshot, target):
    target = Path(target).resolve()
    if target.exists() and (not target.is_dir() or any(target.iterdir())):
        raise BackupError('restore target must be empty')
    target.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(str(target), 0o700)
    sid = snapshot_id(snapshot)
    restic('restore', sid, '--target', str(target))
    manifests = list(target.rglob('manifest.json'))
    if len(manifests) != 1:
        raise BackupError('ambiguous restored recovery manifest')
    verify_stage(manifests[0].parent)
    atomic_json(target / 'RESTORE_VERIFIED.json',
                {'schema_version': 1, 'snapshot_id': sid, 'verified_at': now(),
                 'stage': str(manifests[0].parent), 'production_import_performed': False})
    return sid


def backup(c):
    stage = build_stage(c)
    data = restic('backup', '--json', '--host', HOST, '--tag', TAG, str(stage))
    summaries = [json.loads(line) for line in data.splitlines() if line.strip()]
    summary = next((x for x in reversed(summaries) if x.get('message_type') == 'summary'), None)
    if not summary or not re.fullmatch(r'[0-9a-f]{8,64}', summary.get('snapshot_id', '')):
        raise BackupError('backup did not produce a snapshot receipt')
    # Download this exact snapshot, not merely check the local files we uploaded.
    verify = Path(c['state_dir']) / 'restore-check'
    if verify.exists():
        if verify.is_symlink():
            raise BackupError('unsafe verification directory')
        shutil.rmtree(str(verify))
    restore_stage(summary['snapshot_id'], verify)
    result = save_status(c['state_dir'], 'PASS', snapshot_id=summary['snapshot_id'],
                         download_verified=True, retention_applied=False)
    # No automatic prune before a separate recovery drill: never destroy the sole good copy.
    # A small non-secret inventory outside the encrypted repository survives host loss.
    destination = c['repository'].split(':', 1)[1] + '-inventory/status.json'
    run(['rclone', 'copyto', str(Path(c['state_dir']) / 'status.json'), destination])
    return result


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--config', default='/etc/xyptdq-backup/config.json')
    p.add_argument('command', choices=('init', 'backup', 'check', 'snapshots', 'restore', 'status'))
    p.add_argument('--snapshot', default='latest')
    p.add_argument('--target')
    args = p.parse_args()
    if os.geteuid() != 0:
        raise BackupError('run as root')
    c = load_config(args.config)
    state = Path(c['state_dir'])
    state.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(str(state), 0o700)
    lock = open(str(state / 'operation.lock'), 'w')
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        raise BackupError('another backup or recovery operation is active')
    try:
        if args.command == 'init':
            restic('init')
        elif args.command == 'backup':
            print(json.dumps(backup(c), sort_keys=True))
        elif args.command == 'check':
            restic('check', '--read-data')
        elif args.command == 'snapshots':
            print(restic('snapshots', '--json', '--host', HOST, '--tag', TAG))
        elif args.command == 'restore':
            if not args.target:
                raise BackupError('--target is required')
            print(json.dumps({'snapshot_id': restore_stage(args.snapshot, args.target),
                              'staging_verified': True, 'production_import_performed': False}))
        elif args.command == 'status':
            status = json.loads((state / 'status.json').read_text())
            stamp = (status.get('last_success') or {}).get('finished_at')
            stale = not stamp or (dt.datetime.now(dt.timezone.utc) - dt.datetime.fromisoformat(stamp)).total_seconds() > 36 * 3600
            print(json.dumps({**status, 'stale': stale}))
            if stale or status['outcome'] != 'PASS':
                return 1
    except Exception:
        if args.command == 'backup':
            save_status(state, 'FAIL', error='backup_or_verification_failed')
        raise
    finally:
        lock.close()
    return 0


if __name__ == '__main__':
    os.umask(0o077)
    try:
        sys.exit(main())
    except BackupError as exc:
        print('Backup operation failed: ' + str(exc), file=sys.stderr)
        sys.exit(1)
    except (OSError, ValueError, KeyError):
        # Keep messages generic: subprocess stderr/config data may contain credentials.
        print('Backup operation failed; inspect protected server configuration and journal.', file=sys.stderr)
        sys.exit(1)
