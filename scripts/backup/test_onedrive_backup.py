#!/usr/bin/env python3
"""Behavior regressions: recovery completeness, corruption, failures and snapshot identity."""
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import tarfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('backup', Path(__file__).with_name('onedrive_backup.py'))
b = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(b)


class RecoveryTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def fixture(self, target=None):
        target = target or self.root / 'stage'
        target.mkdir(parents=True)
        website = self.root / 'website'
        website.mkdir(exist_ok=True)
        for name in b.ESSENTIAL:
            p = website / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text('cms recovery data')
        b.archive(target / 'website.tar', website, ['.'], ('./cache/template',))
        for name in ('database.sql', 'runtime.tar', 'system.tar', 'source.bundle',
                     'environment.json', 'root-crontab.txt'):
            (target / name).write_text('fixture ' + name)
        b.atomic_json(target / 'manifest.json', {
            'schema_version': 1, 'sha256': {p.name: b.sha256(p) for p in target.iterdir()}})
        return target

    def test_essential_cache_survives_archive_and_manifest_validation(self):
        stage = self.fixture()
        self.assertEqual(b.verify_stage(stage)['schema_version'], 1)

    def test_changed_database_rejected(self):
        stage = self.fixture()
        (stage / 'database.sql').write_text('corrupted')
        with self.assertRaises(b.BackupError):
            b.verify_stage(stage)

    def test_legacy_whole_cache_exclusion_cannot_pass_recovery_validation(self):
        stage = self.fixture()
        b.archive(stage / 'website.tar', self.root / 'website', ['.'], ('./cache',))
        manifest = json.loads((stage / 'manifest.json').read_text())
        manifest['sha256']['website.tar'] = b.sha256(stage / 'website.tar')
        b.atomic_json(stage / 'manifest.json', manifest)
        with self.assertRaises(b.BackupError):
            b.verify_stage(stage)

    def test_missing_payload_rejected(self):
        stage = self.fixture()
        (stage / 'source.bundle').unlink()
        with self.assertRaises(b.BackupError):
            b.verify_stage(stage)

    def test_incomplete_manifest_rejected(self):
        stage = self.fixture()
        m = json.loads((stage / 'manifest.json').read_text())
        del m['sha256']['runtime.tar']
        b.atomic_json(stage / 'manifest.json', m)
        with self.assertRaises(b.BackupError):
            b.verify_stage(stage)

    def test_failed_run_preserves_previous_success(self):
        b.save_status(self.root, 'PASS', snapshot_id='a' * 64)
        status = b.save_status(self.root, 'FAIL', error='test')
        self.assertEqual(status['outcome'], 'FAIL')
        self.assertEqual(status['last_success']['snapshot_id'], 'a' * 64)

    def test_snapshot_latest_and_prefix_are_filtered_by_host_and_tag(self):
        snapshots = [{'id': 'a' * 64, 'time': '2026-10-30'},
                     {'id': 'b' * 64, 'time': '2026-11-01'}]
        with patch.object(b, 'restic', return_value=json.dumps(snapshots)) as r:
            self.assertEqual(b.snapshot_id('latest'), 'b' * 64)
            self.assertEqual(b.snapshot_id('aaaaaaaa'), 'a' * 64)
            self.assertIn(b.TAG, r.call_args[0])
            self.assertIn(b.HOST, r.call_args[0])

    def test_unknown_snapshot_rejected(self):
        with patch.object(b, 'restic', return_value='[]'):
            with self.assertRaises(b.BackupError):
                b.snapshot_id('latest')

    def test_restore_refuses_nonempty_target(self):
        (self.root / 'existing').write_text('do not overwrite')
        with self.assertRaises(b.BackupError):
            b.restore_stage('latest', self.root)
        self.assertEqual((self.root / 'existing').read_text(), 'do not overwrite')

    def test_download_verified_receipt_uses_exact_snapshot(self):
        target = self.root / 'download'
        def restore(*args):
            self.assertEqual(args[:2], ('restore', 'a' * 64))
            self.fixture(target / 'var/lib/xyptdq-backup/staging')
        with patch.object(b, 'snapshot_id', return_value='a' * 64), patch.object(b, 'restic', side_effect=restore):
            b.restore_stage('aaaaaaaa', target)
        receipt = json.loads((target / 'RESTORE_VERIFIED.json').read_text())
        self.assertEqual(receipt['snapshot_id'], 'a' * 64)
        self.assertFalse(receipt['production_import_performed'])

    def test_corrupt_download_never_receives_verified_marker(self):
        target = self.root / 'bad-download'
        def restore(*args):
            stage = self.fixture(target / 'staging')
            (stage / 'database.sql').write_text('bad download')
        with patch.object(b, 'snapshot_id', return_value='a' * 64), patch.object(b, 'restic', side_effect=restore):
            with self.assertRaises(b.BackupError):
                b.restore_stage('latest', target)
        self.assertFalse((target / 'RESTORE_VERIFIED.json').exists())

    def test_failed_backup_does_not_claim_success(self):
        self.fixture()
        with patch.object(b, 'build_stage', return_value=self.root / 'stage'), \
             patch.object(b, 'restic', side_effect=b.BackupError('failed')), \
             patch.object(b, 'save_status') as status:
            with self.assertRaises(b.BackupError):
                b.backup({'state_dir': str(self.root)})
        status.assert_not_called()

    def test_unsafe_archive_blocks_fresh_host_extraction(self):
        p = self.root / 'unsafe.tar'
        with tarfile.open(str(p), 'w') as tf:
            item = tarfile.TarInfo('../escape')
            item.size = 1
            tf.addfile(item, io.BytesIO(b'x'))
        with self.assertRaises(b.BackupError):
            b.safe_members(p)


if __name__ == '__main__':
    unittest.main(verbosity=2)
