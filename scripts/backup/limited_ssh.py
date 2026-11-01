#!/usr/bin/env python3
"""Install and consume a single-use SSH grant for the OneDrive authorization helper."""
import base64
import datetime as dt
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import struct
import sys
import time

BASE = Path('/var/lib/xyptdq-backup/ssh-grants')
AUTHORIZED = Path('/root/.ssh/authorized_keys')
INSTALLED = '/usr/local/lib/xyptdq-backup/limited_ssh.py'
HELPER = '/usr/local/lib/xyptdq-backup/authorize_ssh.py'
PASSWORD_FILE = Path('/etc/xyptdq-backup/repository-password')
CONFIG_FILE = Path('/etc/xyptdq-backup/config.json')
GRANT_RE = re.compile(r'onedrive-[a-z0-9-]{3,60}')


def validated_key(line):
    parts = line.strip().split()
    if len(parts) not in (2, 3) or parts[0] != 'ssh-ed25519':
        raise ValueError('expected one Ed25519 public key')
    try:
        blob = base64.b64decode(parts[1], validate=True)
    except Exception:
        raise ValueError('invalid public key encoding')
    prefix = struct.pack('>I', 11) + b'ssh-ed25519' + struct.pack('>I', 32)
    if len(blob) != len(prefix) + 32 or not blob.startswith(prefix):
        raise ValueError('invalid Ed25519 public key structure')
    fingerprint = 'SHA256:' + base64.b64encode(hashlib.sha256(blob).digest()).decode().rstrip('=')
    return parts[1], fingerprint


def key_entry(line, grant_id, expires, purpose='authorize'):
    if not GRANT_RE.fullmatch(grant_id):
        raise ValueError('invalid grant identifier')
    blob, fingerprint = validated_key(line)
    if purpose not in ('authorize','export_recovery'):
        raise ValueError('unsupported grant purpose')
    # OpenSSH 8.2 accepts local YYYYMMDDHHMMSS, but does not accept the newer Z suffix.
    expiry = time.strftime('%Y%m%d%H%M%S', time.localtime(expires))
    forced = '/usr/bin/python3 {} use {}'.format(INSTALLED, grant_id)
    options = ['restrict']
    if purpose == 'authorize':
        options += ['port-forwarding', 'permitopen="127.0.0.1:53682"',
                    'permitlisten="127.0.0.1:53682"']
    options += ['command="{}"'.format(forced), 'expiry-time="{}"'.format(expiry)]
    suffix = 'ssh-ed25519 {} xyptdq-{}'.format(blob, grant_id)
    return ','.join(options) + ' ' + suffix + '\n', suffix.encode(), fingerprint


def without_grant(data, suffix):
    return b''.join(line for line in data.splitlines(keepends=True)
                    if not line.rstrip(b'\r\n').endswith(suffix))


def check_root_file(path):
    s = path.lstat()
    if not stat.S_ISREG(s.st_mode) or s.st_uid != 0 or s.st_mode & 0o022:
        raise ValueError('unsafe SSH authorization file')
    return s


def atomic(path, data, mode=0o600):
    tmp = path.with_name(path.name + '.xyptdq-new')
    fd = os.open(str(tmp), os.O_WRONLY | os.O_CREAT | os.O_EXCL, mode)
    try:
        with os.fdopen(fd, 'wb') as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        os.chmod(str(tmp), mode)
        os.replace(str(tmp), str(path))
    finally:
        if tmp.exists():
            tmp.unlink()


def prepare_paths():
    if os.geteuid() != 0:
        raise ValueError('server root is required')
    BASE.mkdir(mode=0o700, parents=True, exist_ok=True)
    BASE.chmod(0o700)
    AUTHORIZED.parent.mkdir(mode=0o700, exist_ok=True)
    s = AUTHORIZED.parent.lstat()
    if not stat.S_ISDIR(s.st_mode) or s.st_uid != 0 or s.st_mode & 0o022:
        raise ValueError('unsafe SSH directory')


def install(line, grant_id, expected_fingerprint, purpose='authorize'):
    prepare_paths()
    with open(str(BASE/'update.lock'), 'a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        return _install_locked(line, grant_id, expected_fingerprint, purpose)


def _install_locked(line, grant_id, expected_fingerprint, purpose):
    expires = int(time.time()) + 7200
    entry, suffix, fingerprint = key_entry(line, grant_id, expires, purpose)
    if fingerprint != expected_fingerprint:
        raise ValueError('public key fingerprint mismatch')
    record = BASE/(grant_id + '.json')
    if record.exists():
        raise ValueError('grant identifier has already been used')
    mode = 0o600
    before = b''
    if AUTHORIZED.exists() or AUTHORIZED.is_symlink():
        mode = stat.S_IMODE(check_root_file(AUTHORIZED).st_mode)
        before = AUTHORIZED.read_bytes()
    blob, _ = validated_key(line)
    if blob.encode() in before:
        raise ValueError('key already has server authorization; preserve existing entry')
    # A root-only backup is for review. Revocation removes only this exact grant.
    atomic(BASE/(grant_id+'.authorized-before'), before)
    grant = {'schema_version':1, 'grant_id':grant_id, 'fingerprint':fingerprint,
             'suffix':suffix.decode(), 'expires_unix':expires, 'used':False,'purpose':purpose}
    atomic(record, (json.dumps(grant, indent=2)+'\n').encode())
    if AUTHORIZED.exists() and AUTHORIZED.read_bytes() != before:
        raise ValueError('SSH authorization file changed concurrently')
    combined = before + (b'\n' if before and not before.endswith(b'\n') else b'') + entry.encode()
    atomic(AUTHORIZED, combined, mode)
    after = AUTHORIZED.read_bytes()
    if without_grant(after, suffix) != before + (b'\n' if before and not before.endswith(b'\n') else b''):
        raise ValueError('existing SSH authorization preservation check failed')
    return {'grant_id':grant_id, 'fingerprint':fingerprint,
            'expires_at':dt.datetime.fromtimestamp(expires,dt.timezone.utc).isoformat(),
            'single_use':True, 'forced_helper_only':True, 'purpose':purpose,
            'authorized_port':53682 if purpose == 'authorize' else None,
            'existing_authorizations_preserved':True, 'server_password_changed':False}


def consume(grant_id):
    prepare_paths()
    if not GRANT_RE.fullmatch(grant_id):
        raise ValueError('invalid grant identifier')
    with open(str(BASE/'update.lock'), 'a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        grant = _consume_locked(grant_id)
    if grant.get('purpose','authorize') == 'export_recovery':
        payload = export_recovery(grant)
        sys.stdout.write(payload.decode('ascii'))
        sys.stdout.flush()
        return
    # Existing authenticated SSH session keeps its restricted forwarding rights.
    # The key has already been revoked before the browser authorization starts.
    os.execv('/usr/bin/python3', ['/usr/bin/python3', HELPER])


def _consume_locked(grant_id):
    record = BASE/(grant_id+'.json')
    check_root_file(record)
    grant = json.loads(record.read_text())
    if grant.get('used') or time.time() >= grant['expires_unix']:
        raise ValueError('authorization grant expired or already used')
    purpose = grant.get('purpose','authorize')
    expected = {'authorize':'authorize-onedrive','export_recovery':'export-recovery-key'}.get(purpose)
    if not expected or os.environ.get('SSH_ORIGINAL_COMMAND','').strip() != expected:
        raise ValueError('request does not match authorized operation')
    check_root_file(AUTHORIZED)
    original = AUTHORIZED.read_bytes()
    revised = without_grant(original, grant['suffix'].encode())
    if revised == original:
        raise ValueError('authorization grant is absent')
    atomic(AUTHORIZED, revised, stat.S_IMODE(AUTHORIZED.stat().st_mode))
    grant['used'] = True
    grant['used_at'] = dt.datetime.now(dt.timezone.utc).isoformat()
    atomic(record, (json.dumps(grant, indent=2)+'\n').encode())
    return grant


def export_recovery(grant):
    # Called only after an authenticated one-use SSH grant is consumed. Never run by a bridge task.
    for path in (PASSWORD_FILE,CONFIG_FILE):
        if check_root_file(path).st_mode & 0o077:
            raise ValueError('recovery configuration must be private')
    password = PASSWORD_FILE.read_text().strip()
    if len(password) < 24 or '\n' in password or '\x00' in password:
        raise ValueError('unexpected recovery password format')
    cfg = json.loads(CONFIG_FILE.read_text())
    if not str(cfg.get('repository','')).startswith('rclone:onedrive:WebsiteBackups/xyptdq/'):
        raise ValueError('unexpected recovery repository')
    envelope = {'schema_version':1,'project':'xyptdq','repository':cfg['repository'],
                'repository_password':password,
                'created_at':dt.datetime.now(dt.timezone.utc).isoformat(),
                'source_repository':'https://github.com/fdsasaaa/xyptdq',
                'runbook':'docs/ops/ONEDRIVE_BACKUP_RECOVERY.md'}
    payload = (json.dumps(envelope,sort_keys=True,separators=(',',':'),ensure_ascii=True)+'\n').encode('ascii')
    atomic(BASE/(grant['grant_id']+'.recovery.json'),payload)
    grant['recovery_file_sha256'] = hashlib.sha256(payload).hexdigest()
    grant['recovery_file_bytes'] = len(payload)
    grant['exported_at'] = dt.datetime.now(dt.timezone.utc).isoformat()
    atomic(BASE/(grant['grant_id']+'.json'),(json.dumps(grant,indent=2)+'\n').encode())
    return payload


if __name__ == '__main__':
    os.umask(0o077)
    try:
        if len(sys.argv) != 3 or sys.argv[1] != 'use':
            raise ValueError('unsupported operation')
        consume(sys.argv[2])
    except (OSError, ValueError, KeyError):
        print('Temporary authorization unavailable or already used; return to ChatGPT.', file=sys.stderr)
        sys.exit(1)
