import hashlib
import importlib.util
import json
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('escrow', Path(__file__).with_name('recovery_escrow.py'))
escrow = importlib.util.module_from_spec(spec)
spec.loader.exec_module(escrow)


class RecoveryEscrowTests(unittest.TestCase):
    def setUp(self):
        self.repository = 'rclone:onedrive:WebsiteBackups/xyptdq/restic-v1'
        self.password = 'test-only-recovery-password'
        self.payload = (json.dumps({'schema_version': 1, 'project': 'xyptdq',
                                    'repository': self.repository,
                                    'repository_password': self.password}) + '\n').encode('ascii')
        self.sha = hashlib.sha256(self.payload).hexdigest()
        self.grant = {'purpose': 'export_recovery', 'used': True, 'exported_at': '2026-11-01',
                      'grant_id': 'onedrive-recovery-test', 'recovery_file_sha256': self.sha,
                      'recovery_file_bytes': len(self.payload)}

    def verify(self, sha=None, payload=None, password=None):
        return escrow.verify_export(self.grant, self.payload if payload is None else payload,
                                    self.sha if sha is None else sha, self.repository,
                                    self.password if password is None else password)

    def test_windows_uppercase_hash_matches_and_result_has_no_password(self):
        result = self.verify(sha=self.sha.upper())
        self.assertTrue(result['current_repository_key_verified'])
        self.assertNotIn(self.password, json.dumps(result))
        self.assertNotIn('repository_password', result)

    def test_bom_or_changed_newline_is_not_accepted_as_identical(self):
        for changed in (b'\xef\xbb\xbf' + self.payload, self.payload[:-1] + b'\r\n'):
            with self.assertRaises(ValueError):
                self.verify(payload=changed)

    def test_different_owner_file_is_rejected(self):
        with self.assertRaises(ValueError):
            self.verify(sha='0' * 64)

    def test_authorization_or_unconsumed_grant_is_not_escrow(self):
        for updates in ({'purpose': 'authorize'}, {'used': False}, {'exported_at': None}):
            original = self.grant.copy()
            self.grant.update(updates)
            with self.assertRaises(ValueError):
                self.verify()
            self.grant = original

    def test_old_password_is_rejected_even_if_file_hash_matches(self):
        with self.assertRaises(ValueError):
            self.verify(password='a-different-current-password')

    def test_export_receipt_tampering_is_rejected(self):
        self.grant['recovery_file_bytes'] += 1
        with self.assertRaises(ValueError):
            self.verify()


if __name__ == '__main__':
    unittest.main(verbosity=2)
