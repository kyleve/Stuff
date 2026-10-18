from copy import deepcopy
import unittest

from Tools.InstallerKit.installer_site_data import prepare_site
from Tools.Tests.Fixtures.installer_update_fixtures import catalog, multiple_apps, FEED_URL, REPO


class InstallerSiteDataTests(unittest.TestCase):
    def test_duplicate_out_of_order_or_empty_active_channels_fail(self):
        original = catalog()
        duplicates = deepcopy(original)
        duplicates["apps"][0]["channels"] += duplicates["apps"][0]["channels"]
        unordered = deepcopy(original)
        unordered["apps"][0]["channels"][0]["releases"].reverse()
        empty = deepcopy(original)
        empty["apps"][0]["channels"][0]["releases"] = []
        for value in (duplicates, unordered, empty):
            with self.assertRaises(ValueError):
                prepare_site(value, REPO, FEED_URL)

    def test_rejects_app_collisions_and_cross_app_manifest_urls(self):
        duplicate = multiple_apps()
        duplicate["apps"][1]["id"] = "where"
        duplicate_bundle = multiple_apps()
        duplicate_bundle["apps"][1]["bundleIdentifier"] = duplicate_bundle["apps"][0]["bundleIdentifier"]
        wrong_manifest = multiple_apps()
        wrong_manifest["apps"][1]["channels"][0]["releases"][0]["manifestURL"] = wrong_manifest["apps"][0]["channels"][0]["releases"][0]["manifestURL"]
        for value in (duplicate, duplicate_bundle, wrong_manifest):
            with self.assertRaises(ValueError):
                prepare_site(value, REPO, FEED_URL)

    def test_retired_channel_carries_no_install_action_but_preserves_public_history(self):
        value = catalog()
        value["apps"][0]["channels"][1]["active"] = False
        prepared = prepare_site(value, REPO, FEED_URL)
        retired = prepared.data["apps"][0]["channels"][1]
        self.assertEqual(retired, {"name": "pr-42", "state": "retired"})
        self.assertNotIn("manifests/where/pr-42/2-1.plist", prepared.files)
        self.assertIn(b"pr-42", prepared.files["updates.json"])

    def test_commit_links_reject_invalid_identity_and_subject_before_rendering(self):
        for changes in ({"sha": "../../bad"}, {"subject": {"html": "bad"}}):
            value = catalog()
            value["apps"][0]["channels"][0]["releases"][0]["commits"][0].update(changes)
            with self.subTest(changes=changes), self.assertRaisesRegex(ValueError, "Invalid commit"):
                prepare_site(value, REPO, FEED_URL)
