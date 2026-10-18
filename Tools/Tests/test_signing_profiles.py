from datetime import datetime, timezone
import json
from pathlib import Path
import plistlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from Tools.InstallerKit.signing_profiles import Target, prepare, read_profile, validate_settings

TARGETS = (Target("Where", "TUIST_WHERE_ADHOC_APP_PROFILE"),
           Target("WhereWidgets", "TUIST_WHERE_ADHOC_WIDGET_PROFILE"),
           Target("WhereShareExtension", "TUIST_WHERE_ADHOC_SHARE_PROFILE"))
REQUIRED = {"WHERE_AUDIENCE": "development"}
from Fixtures.where_distribution_fixtures import profile, write_profiles


NOW = datetime(2026, 1, 1, tzinfo=timezone.utc)


class WhereSigningTests(unittest.TestCase):
    def test_prepare_derives_export_and_profiles_without_device_identifiers(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            write_profiles(root / "profiles")
            prepare(root / "profiles", root / "plan", NOW, TARGETS)
            export = plistlib.loads((root / "plan/ExportOptions.plist").read_bytes())
            self.assertEqual(export["method"], "ad-hoc")
            self.assertEqual(export["signingStyle"], "manual")
            self.assertEqual(len(export["provisioningProfiles"]), 3)
            profiles = json.loads((root / "plan/profiles.json").read_text())
            self.assertEqual(profiles[2]["uuid"], profile(2)["UUID"])
            self.assertEqual(profiles[0]["team"], "TESTTEAM01")
            self.assertNotIn("fixture-device", (root / "plan/profiles.json").read_text())

    def test_rejects_expired_development_enterprise_store_and_wildcard_profiles(self):
        mutations = [
            {"ExpirationDate": datetime(2025, 1, 1)},
            {"Entitlements": {"get-task-allow": True}},
            {"ProvisionsAllDevices": True},
            {"ProvisionedDevices": []},
            {"ApplicationIdentifierPrefix": "TESTTEAM01"},
            {"UUID": "invalid; command"},
            {"Entitlements": {"get-task-allow": False, "application-identifier": "TESTTEAM01.*"}},
        ]
        for mutation in mutations:
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                read_profile(TARGETS[0], {**profile(0), **mutation}, NOW)

    def test_cross_profile_mismatch_does_not_create_output(self):
        for mutation in ({"TeamIdentifier": ["OTHERTEAM1"]},
                         {"ProvisionedDevices": ["different-device"]},
                         {"UUID": profile(0)["UUID"]},
                         {"Entitlements": profile(0)["Entitlements"]}):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                write_profiles(root / "profiles")
                (root / "profiles/WhereWidgets.plist").write_bytes(plistlib.dumps({**profile(1), **mutation}))
                with self.assertRaises(ValueError):
                    prepare(root / "profiles", root / "output", NOW, TARGETS)
                self.assertFalse((root / "output").exists())

    def test_generated_target_settings_must_match_every_signing_field(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            write_profiles(root / "profiles")
            prepare(root / "profiles", root / "plan", NOW, TARGETS)
            profiles = json.loads((root / "plan/profiles.json").read_text())
            settings = [{"target": item["target"], "buildSettings": {
                "PRODUCT_BUNDLE_IDENTIFIER": item["bundle_id"], "DEVELOPMENT_TEAM": item["team"],
                "PROVISIONING_PROFILE_SPECIFIER": item["uuid"], "CODE_SIGN_STYLE": "Manual",
                "WHERE_AUDIENCE": "development"}} for item in profiles]
            validate_settings(settings, profiles, REQUIRED)
            for key in settings[0]["buildSettings"]:
                changed = json.loads(json.dumps(settings))
                changed[1]["buildSettings"][key] = "wrong"
                with self.subTest(key=key), self.assertRaises(ValueError):
                    validate_settings(changed, profiles, REQUIRED)
            with self.assertRaises(ValueError):
                validate_settings(settings[:1], profiles, REQUIRED)
