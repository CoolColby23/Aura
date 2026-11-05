import datetime
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('profiles', Path(__file__).resolve().parents[2] / 'scripts/verify-widget-profiles.py')
profiles = importlib.util.module_from_spec(spec)
spec.loader.exec_module(profiles)

class WidgetProfilesTests(unittest.TestCase):
    def test_requires_current_explicit_bundle_and_group(self):
        now = datetime.datetime(2026, 1, 1)
        profile = {'TeamIdentifier': ['TEAM'], 'ExpirationDate': now + datetime.timedelta(days=1), 'DeveloperCertificates': [b'authorized-public-der'], 'Entitlements': {'com.apple.application-identifier': 'TEAM.fm.aura.Aura.Widget', 'com.apple.security.application-groups': [profiles.GROUP]}}
        self.assertEqual(profiles.validate(profile, 'fm.aura.Aura.Widget', profiles.fingerprint(b'authorized-public-der'), now), 'TEAM')
        for key, value in [('com.apple.application-identifier', 'TEAM.*'), ('com.apple.security.application-groups', [])]:
            copy = {**profile, 'Entitlements': {**profile['Entitlements'], key: value}}
            with self.assertRaises(ValueError):
                profiles.validate(copy, 'fm.aura.Aura.Widget', profiles.fingerprint(b'authorized-public-der'), now)
        for certificates in [[], [b'older-renewed-public-der']]:
            with self.assertRaises(ValueError):
                profiles.validate({**profile, 'DeveloperCertificates': certificates}, 'fm.aura.Aura.Widget', profiles.fingerprint(b'authorized-public-der'), now)
        with self.assertRaises(ValueError):
            profiles.validate(profile, 'fm.aura.Aura.Widget', profiles.fingerprint(b'authorized-public-der'), now + datetime.timedelta(days=2))

if __name__ == '__main__':
    unittest.main()
