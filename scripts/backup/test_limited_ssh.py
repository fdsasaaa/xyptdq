import importlib.util
from pathlib import Path
import re
import json
import tempfile
import time
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('limited',Path(__file__).with_name('limited_ssh.py'))
limited = importlib.util.module_from_spec(spec)
spec.loader.exec_module(limited)
KEY = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID65vJ4Tvq5+Ea1xELuwTjR2EhKl59QWB7PbMCo/msxr xyptdq-onedrive-once'


class LimitedSSHTests(unittest.TestCase):
    def test_matches_owner_provided_fingerprint(self):
        self.assertEqual(limited.validated_key(KEY)[1], 'SHA256:6noVoCRkDD1Gh5lII16ZEWKtGH9Xz4JHtV/X0eJT8WI')

    def test_rejects_malformed_keys(self):
        for key in ('ssh-rsa AAAA', 'ssh-ed25519 AAAA', KEY+' extra-field'):
            with self.assertRaises(ValueError):
                limited.validated_key(key)

    def test_command_and_tunnels_are_restricted(self):
        line, suffix, _ = limited.key_entry(KEY,'onedrive-20261101-01',1793500000)
        self.assertTrue(line.startswith('restrict,port-forwarding,'))
        self.assertIn('permitopen="127.0.0.1:53682"',line)
        self.assertIn('permitlisten="127.0.0.1:53682"',line)
        self.assertIn('command="/usr/bin/python3 /usr/local/lib/xyptdq-backup/limited_ssh.py use onedrive-20261101-01"',line)
        self.assertRegex(line,r'expiry-time="[0-9]{14}"')
        self.assertTrue(line.rstrip().encode().endswith(suffix))

    def test_revocation_preserves_all_other_entries(self):
        line, suffix, _ = limited.key_entry(KEY,'onedrive-20261101-01',1793500000)
        other = b'# existing operator\nssh-ed25519 OTHER existing\r\n'
        self.assertEqual(limited.without_grant(other+line.encode(),suffix),other)
        self.assertEqual(limited.without_grant(other,suffix),other)

    def test_grant_identifier_cannot_change_forced_command(self):
        for grant in ('../bad','onedrive-valid;sh','onedrive-x\ncommand'):
            with self.assertRaises(ValueError):
                limited.key_entry(KEY,grant,1793500000)

    def test_first_use_revokes_key_before_starting_helper_and_cannot_repeat(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            authorized = root/'authorized_keys'
            grant_id = 'onedrive-fixture-01'
            line, suffix, _ = limited.key_entry(KEY,grant_id,time.time()+600)
            prior = b'# existing operator\nssh-ed25519 OTHER existing\n'
            authorized.write_bytes(prior+line.encode())
            record = root/(grant_id+'.json')
            record.write_text(json.dumps({'suffix':suffix.decode(),'used':False,'expires_unix':time.time()+600}))
            with patch.object(limited,'BASE',root), patch.object(limited,'AUTHORIZED',authorized), \
                 patch.object(limited,'prepare_paths'), patch.object(limited,'check_root_file',lambda p:p.stat()), \
                 patch.object(limited.os,'execv') as execute:
                limited.consume(grant_id)
                self.assertEqual(authorized.read_bytes(),prior)
                self.assertTrue(json.loads(record.read_text())['used'])
                execute.assert_called_once_with('/usr/bin/python3',['/usr/bin/python3',limited.HELPER])
                with self.assertRaises(ValueError):
                    limited.consume(grant_id)

    def test_expired_grant_cannot_start_helper(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            grant_id = 'onedrive-expired-01'
            (root/(grant_id+'.json')).write_text(json.dumps({'used':False,'expires_unix':time.time()-1}))
            with patch.object(limited,'BASE',root), patch.object(limited,'prepare_paths'), \
                 patch.object(limited,'check_root_file',lambda p:p.stat()), patch.object(limited.os,'execv') as execute:
                with self.assertRaises(ValueError):
                    limited.consume(grant_id)
                execute.assert_not_called()


if __name__ == '__main__':
    unittest.main(verbosity=2)
