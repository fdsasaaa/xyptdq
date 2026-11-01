import importlib.util
from pathlib import Path
import unittest
spec=importlib.util.spec_from_file_location('select_drive',Path(__file__).with_name('select_default_drive.py'))
m=importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

class DefaultDriveTests(unittest.TestCase):
    def question(self):
        return {'State':'driveid_final','Option':{'Name':'config_driveid','Examples':[{'Value':'shared-a'},{'Value':'owner-default'}]}}
    def test_exact_default_id_is_selected(self):
        self.assertEqual(m.default_drive_id(self.question(),{'id':'owner-default','driveType':'personal'}),'owner-default')
    def test_shared_library_is_not_selected(self):
        with self.assertRaises(ValueError):
            m.default_drive_id(self.question(),{'id':'shared-a','driveType':'documentLibrary'})
    def test_missing_default_is_not_guessed_by_position(self):
        with self.assertRaises(ValueError):
            m.default_drive_id(self.question(),{'id':'absent','driveType':'business'})
    def test_duplicate_identity_is_rejected(self):
        q=self.question()
        q['Option']['Examples'].append({'Value':'owner-default'})
        with self.assertRaises(ValueError):
            m.default_drive_id(q,{'id':'owner-default','driveType':'personal'})
    def test_unexpected_provider_stage_is_not_confirmed(self):
        with self.assertRaises(ValueError):
            m.default_drive_id({'State':'other','Option':{'Name':'config_type'}},{'id':'owner-default','driveType':'personal'})

if __name__=='__main__':
    unittest.main(verbosity=2)
