#!/usr/bin/env python3
"""Run only over the owner's SSH tunnel; OAuth links never enter public receipts."""
import configparser
import datetime as dt
import fcntl
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time
from urllib.parse import parse_qs, urlparse

BASE = Path('/var/lib/xyptdq-backup')
CONFIG = Path('/etc/xyptdq-backup/rclone.conf')
RCLONE = '/usr/local/bin/rclone'


class SetupError(Exception):
    pass


def find_login_url(log):
    for url in re.findall(r'http://127\.0\.0\.1:53682/auth\?[^\s\x1b]+', log):
        parsed = urlparse(url)
        q = parse_qs(parsed.query)
        if parsed.hostname == '127.0.0.1' and parsed.port == 53682 and parsed.path == '/auth' \
                and set(q) == {'state'} and len(q['state']) == 1 and 16 <= len(q['state'][0]) <= 256:
            return url
    return None


def choose_result(question, ask=input):
    option = question.get('Option') or {}
    name = option.get('Name')
    if name == 'config_is_local':
        return 'true'
    if name == 'config_type':
        return 'onedrive'
    if name == 'config_drive_ok':
        return 'true'
    if name == 'config_driveid':
        examples = option.get('Examples') or []
        if not examples:
            raise SetupError('NO_DRIVE_FOUND')
        if len(examples) == 1:
            return examples[0]['Value']
        print('Multiple drives found. Select the drive you own:')
        for i, example in enumerate(examples, 1):
            label = ''.join(x for x in str(example.get('Help', 'OneDrive')) if x.isprintable())
            print('  {}. {}'.format(i, label[:300]))
        answer = ask('Drive number: ').strip()
        if not answer.isdigit() or not 1 <= int(answer) <= len(examples):
            raise SetupError('DRIVE_SELECTION_REQUIRED')
        return examples[int(answer)-1]['Value']
    raise SetupError('UNEXPECTED_PROVIDER_STEP')


def save_status(status, **fields):
    # Fixed whitelist: no provider object, URL, account name, drive ID or auth data.
    allowed = ('drive_type', 'total_bytes', 'free_bytes', 'used_bytes')
    result = {'schema_version': 1, 'task': 'onedrive_ssh_authorization',
              'status': status, 'observed_at': dt.datetime.now(dt.timezone.utc).isoformat(),
              'remote_snapshot_created': False, 'daily_timer_enabled': False}
    result.update({k: fields[k] for k in allowed if k in fields})
    path = BASE / 'onedrive-auth-status.json'
    tmp = path.with_suffix('.new')
    tmp.write_text(json.dumps(result, indent=2) + '\n')
    tmp.chmod(0o600)
    os.replace(str(tmp), str(path))
    settings = json.loads(Path('/etc/xyptdq-backup/config.json').read_text())
    public_root = Path(settings['webroot']) / 'uploadfile/xyptdq-agent-results'
    if public_root.is_dir():
        public = public_root / 'onedrive-oauth-status.json'
        tmp = public_root / '.onedrive-oauth-status.new'
        tmp.write_text(json.dumps(result, indent=2) + '\n')
        tmp.chmod(0o644)
        os.replace(str(tmp), str(public))


def invoke(arguments):
    out = BASE / 'onedrive-auth-response.json'
    log = BASE / 'onedrive-auth-private.log'
    shown = False
    with open(str(out), 'w') as stdout, open(str(log), 'w') as stderr:
        process = subprocess.Popen([RCLONE, '--config', str(CONFIG)] + arguments,
                                   stdin=subprocess.DEVNULL, stdout=stdout, stderr=stderr)
        try:
            deadline = time.monotonic() + 1200
            while process.poll() is None:
                if not shown:
                    url = find_login_url(log.read_text(errors='replace'))
                    if url:
                        print('\nOpen this link in the browser on THIS Windows computer:', flush=True)
                        print(url, flush=True)
                        print('Sign in to the Microsoft account that owns the backup storage.', flush=True)
                        print('Keep this PowerShell window open. Do not send the link or OAuth output to chat.', flush=True)
                        save_status('WAITING_BROWSER_LOGIN')
                        shown = True
                if time.monotonic() > deadline:
                    raise SetupError('LOGIN_TIMED_OUT_RERUN_SSH_COMMAND')
                time.sleep(0.5)
            if process.returncode != 0:
                raise SetupError('RCLONE_CONFIGURATION_FAILED')
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=8)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
    try:
        question = json.loads(out.read_text())
    except ValueError:
        raise SetupError('PROVIDER_RESPONSE_REQUIRES_PRIVATE_REVIEW')
    if question is None:
        question = {}
    if not isinstance(question, dict):
        raise SetupError('PROVIDER_RESPONSE_REQUIRES_PRIVATE_REVIEW')
    if question.get('Error'):
        raise SetupError('PROVIDER_REPORTED_ERROR')
    return question


def main():
    if os.geteuid() != 0:
        raise SetupError('RUN_AS_SERVER_ROOT')
    BASE.mkdir(mode=0o700, exist_ok=True)
    lock = open(str(BASE/'onedrive-auth.lock'), 'a')
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        raise SetupError('ANOTHER_AUTHORIZATION_IS_ACTIVE')
    for sig in (signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, lambda signum, frame: sys.exit(1))
    c = configparser.ConfigParser(interpolation=None)
    c.read(str(CONFIG))
    if c.get('onedrive', 'type', fallback='') != 'onedrive':
        raise SetupError('SERVER_REMOTE_NOT_PREPARED')
    existing = bool(c.get('onedrive', 'token', fallback='').strip())
    complete = existing and bool(c.get('onedrive', 'drive_id', fallback='').strip())
    if not complete:
        args = ['config', 'update', 'onedrive', 'config_is_local', 'true',
                'config_auth_no_browser', 'true', '--non-interactive']
        if existing:
            args[3:3] = ['config_refresh_token', 'false']
        q = invoke(args)
        for _ in range(10):
            if not q.get('State'):
                break
            answer = choose_result(q)
            q = invoke(['config', 'update', 'onedrive', 'config_is_local', 'true',
                        'config_auth_no_browser', 'true', '--non-interactive', '--continue',
                        '--state', q['State'], '--result', str(answer)])
        else:
            raise SetupError('PROVIDER_STEP_LIMIT_REACHED')
    CONFIG.chmod(0o600)
    c.read(str(CONFIG))
    if not c.get('onedrive', 'token', fallback='') or not c.get('onedrive','drive_id',fallback=''):
        raise SetupError('AUTHORIZATION_NOT_COMPLETE')
    p = subprocess.run([RCLONE, '--config', str(CONFIG), 'about', 'onedrive:', '--json'],
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                       universal_newlines=True, timeout=120)
    if p.returncode:
        raise SetupError('AUTHORIZATION_SAVED_CAPACITY_CHECK_FAILED')
    quota = json.loads(p.stdout)
    save_status('AUTHORIZED_AND_CAPACITY_VERIFIED',
                drive_type=c.get('onedrive','drive_type',fallback='unknown'),
                **{dst:quota[src] for src,dst in [('total','total_bytes'),('free','free_bytes'),('used','used_bytes')] if src in quota})
    print('\nMicrosoft authorization completed and storage capacity verified.', flush=True)
    print('Return to ChatGPT and say: authorization completed. No cloud backup has run yet.', flush=True)
    lock.close()


if __name__ == '__main__':
    os.umask(0o077)
    try:
        main()
    except SetupError as exc:
        try:
            save_status(str(exc))
        except Exception:
            pass
        print('Setup status: ' + str(exc), file=sys.stderr)
        sys.exit(1)
    except (OSError, ValueError, KeyError, subprocess.TimeoutExpired):
        try:
            save_status('SETUP_FAILED_REQUIRES_PRIVATE_REVIEW')
        except Exception:
            pass
        print('Setup failed. Return only this error line to ChatGPT.', file=sys.stderr)
        sys.exit(1)
