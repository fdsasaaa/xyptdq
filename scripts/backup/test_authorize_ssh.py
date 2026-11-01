import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('auth', Path(__file__).with_name('authorize_ssh.py'))
auth = importlib.util.module_from_spec(spec)
spec.loader.exec_module(auth)


class AuthorizationTests(unittest.TestCase):
    def test_only_loopback_auth_link_is_returned(self):
        expected = 'http://127.0.0.1:53682/auth?state=0123456789abcdef1234'
        self.assertEqual(auth.find_login_url('NOTICE: ' + expected + '\n'), expected)
        self.assertIsNone(auth.find_login_url('https://example.com/auth?state=0123456789abcdef'))

    def test_wrong_query_and_short_state_are_rejected(self):
        self.assertIsNone(auth.find_login_url('http://127.0.0.1:53682/auth?state=short'))
        self.assertIsNone(auth.find_login_url('http://127.0.0.1:53682/auth?state=0123456789abcdef&code=private'))

    def test_single_drive_does_not_require_manual_choice(self):
        q = {'Option': {'Name':'config_driveid', 'Examples':[{'Value':'drive-a'}]}}
        self.assertEqual(auth.choose_result(q, lambda _: self.fail('unexpected question')), 'drive-a')

    def test_multiple_drives_require_an_explicit_valid_selection(self):
        q = {'Option': {'Name':'config_driveid', 'Examples':[{'Value':'a'}, {'Value':'b'}]}}
        self.assertEqual(auth.choose_result(q, lambda _: '2'), 'b')
        with self.assertRaises(auth.SetupError):
            auth.choose_result(q, lambda _: '7')

    def test_unknown_provider_options_never_get_auto_confirmed(self):
        with self.assertRaises(auth.SetupError):
            auth.choose_result({'Option': {'Name':'unknown'}})
        self.assertEqual(auth.choose_result({'Option': {'Name':'config_type'}}), 'onedrive')
        self.assertEqual(auth.choose_result({'Option': {'Name':'config_drive_ok'}}), 'true')


if __name__ == '__main__':
    unittest.main(verbosity=2)
