from copy import deepcopy
import json
from pathlib import Path
import tempfile
import unittest

from Tools.InstallerKit.github_releases import GitHubReleases, asset_url
from Fixtures.github_releases_fixtures import ReleaseServer


class GitHubReleasesTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.ipa = Path(self.temporary.name) / "Where.ipa"
        self.ipa.write_bytes(b"signed IPA fixture")
        self.server = ReleaseServer()
        self.publisher = GitHubReleases("fixture/Stuff", "fixture-token", self.server)

    def publish(self):
        return self.publisher.publish(self.ipa, "where", "pr-42", {"run": 12, "attempt": 1}, "a" * 40, "Where Dev")

    def test_upload_verifies_digest_before_publishing_and_targets_trusted_main(self):
        url = self.publish()
        self.assertEqual(url, asset_url("fixture/Stuff", "where", "pr-42", {"run": 12, "attempt": 1}))
        writes = [request for request in self.server.requests if request.method != "GET"]
        self.assertEqual([request.method for request in writes], ["POST", "POST", "PATCH"])
        create = json.loads(writes[0].data)
        self.assertTrue(create["draft"])
        self.assertTrue(create["prerelease"])
        self.assertEqual(create["make_latest"], "false")
        self.assertEqual(create["target_commitish"], "b" * 40)
        self.assertIn("/commit/" + "a" * 40, create["body"])
        self.assertEqual(writes[1].host, "uploads.github.com")
        self.assertEqual(writes[1].data, self.ipa.read_bytes())
        self.assertFalse(self.server.release["draft"])
        self.assertEqual(self.server.requests[-1].method, "GET")
        self.assertIn("/assets?", self.server.requests[-1].full_url)

    def test_retry_reuses_verified_draft_or_published_asset_without_overwriting(self):
        self.publish()
        for draft in (True, False):
            self.server.release["draft"] = draft
            self.server.requests.clear()
            self.publish()
            writes = [request.method for request in self.server.requests if request.method != "GET"]
            self.assertEqual(writes, ["PATCH"] if draft else [])

    def test_private_repository_fails_before_mutation(self):
        self.server.private = True
        with self.assertRaisesRegex(ValueError, "public release repository"):
            self.publish()
        self.assertTrue(all(request.method == "GET" for request in self.server.requests))

    def test_unverified_asset_never_publishes(self):
        for changes in ({"digest": "sha256:wrong"}, {"state": "starter"}, {"size": 0},
                        {"id": None}, {"id": True}, {"id": 0},
                        {"browser_download_url": "https://evil.example/Where.ipa"},
                        {"browser_download_url": "https://github.com/other/Stuff/releases/download/untagged-draft/app.ipa"},
                        {"browser_download_url": "https://github.com/fixture/Stuff/releases/download/untagged-draft/other.ipa"}):
            with self.subTest(changes=changes):
                self.server = ReleaseServer(asset_changes=changes)
                self.publisher = GitHubReleases("fixture/Stuff", "fixture-token", self.server)
                with self.assertRaisesRegex(ValueError, "verification failed"):
                    self.publish()
                self.assertFalse(any(request.method == "PATCH" for request in self.server.requests))

    def test_interrupted_publication_reuses_uploaded_draft_with_temporary_url(self):
        self.server.fail_publish = True
        with self.assertRaisesRegex(ValueError, "publication interrupted"):
            self.publish()
        self.assertTrue(self.server.release["draft"])
        self.assertIn("/untagged-", self.server.assets[0]["browser_download_url"])
        self.server.fail_publish = False
        self.server.requests.clear()
        self.publish()
        self.assertEqual([request.method for request in self.server.requests if request.method != "GET"], ["PATCH"])
        self.assertFalse(self.server.release["draft"])

    def test_published_asset_is_verified_again_before_returning_install_url(self):
        for changes in ({"digest": "sha256:wrong"}, {"size": 0}, {"state": "starter"},
                        {"browser_download_url": "https://github.com/fixture/Stuff/releases/download/untagged-draft/app.ipa"},
                        {"browser_download_url": "https://evil.example/app.ipa"}):
            with self.subTest(changes=changes):
                self.server = ReleaseServer()
                self.server.published_asset_changes = changes
                self.publisher = GitHubReleases("fixture/Stuff", "fixture-token", self.server)
                with self.assertRaises(ValueError):
                    self.publish()
                self.assertFalse(self.server.release["draft"])
                self.server.requests.clear()
                with self.assertRaises(ValueError):
                    self.publish()
                self.assertTrue(all(request.method == "GET" for request in self.server.requests))

    def test_publication_cannot_replace_the_verified_asset(self):
        self.server.published_asset_changes = {"id": 789}
        with self.assertRaisesRegex(ValueError, "identity changed"):
            self.publish()

    def test_failed_upload_can_resume_but_never_reports_success(self):
        self.server.fail_upload = True
        with self.assertRaisesRegex(ValueError, "upload failed"):
            self.publish()
        self.assertTrue(self.server.release["draft"])
        self.server.fail_upload = False
        self.publish()
        self.assertFalse(self.server.release["draft"])

    def test_changed_ipa_or_release_metadata_are_not_overwritten(self):
        self.publish()
        original = deepcopy(self.server.release)
        for changes in ({"body": "another build"}, {"prerelease": False}, {"tag_name": "other"}):
            self.server.release = {**original, **changes}
            with self.assertRaisesRegex(ValueError, "does not match"):
                self.publish()
        self.server.release = original
        self.ipa.write_bytes(b"different build")
        with self.assertRaisesRegex(ValueError, "does not match"):
            self.publish()

    def test_path_injection_and_invalid_build_id_are_rejected(self):
        for repository in ("owner/../../repo", "owner/repo?secret", "owner\\repo"):
            with self.assertRaises(ValueError):
                GitHubReleases(repository, "token")
        for channel, identifier in (("../main", {"run": 1, "attempt": 1}),
                                    ("main", {"run": True, "attempt": 1}),
                                    ("main", {"run": 1, "attempt": 0})):
            with self.assertRaises(ValueError):
                self.publisher.publish(self.ipa, "where", channel, identifier, "a" * 40, "notes")
        self.assertEqual(self.server.requests, [])
