from dataclasses import replace
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

from Tools.InstallerKit import installer_ci
from Tools.InstallerKit.github_releases import asset_url
from Tools.InstallerKit.installer_update_feed import build_id
from Fixtures.circleci_distribution_fixtures import (
    archive_request,
    write_archive,
    pull_request,
)


class InstallerCITests(unittest.TestCase):
    def setUp(self):
        self.request = archive_request()
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.ipa = self.root / "app.ipa"
        write_archive(self.ipa)
        self.feed = Mock(repository=self.request.repository)
        self.fetch = Mock(return_value=pull_request())
        self.releases = Mock()
        self.releases.publish.return_value = asset_url(
            self.request.repository, "where", "pr-42", build_id("12", "2")
        )

    def test_verified_native_archive_publishes_exact_identity(self):
        with patch("Tools.InstallerKit.installer_ci.publish_receipt") as publish:
            summary = installer_ci.complete(
                self.request,
                self.ipa,
                self.feed,
                self.fetch,
                self.releases,
                "https://app.circleci.com/pipelines/circleci/org/project/321",
            )
        self.assertIn("pr-42", summary)
        receipt = publish.call_args.args[0]
        self.assertEqual(
            (receipt["appID"], receipt["run"], receipt["attempt"], receipt["sha"]),
            ("where", "12", "2", self.request.sha),
        )
        self.assertEqual(
            receipt["workflowURL"],
            "https://app.circleci.com/pipelines/circleci/org/project/321",
        )
        self.releases.publish.assert_called_once()

    def test_wrong_or_missing_archive_reports_failure_without_publishing(self):
        for request, path in [
            (replace(self.request, run="13"), self.ipa),
            (self.request, self.root / "absent.ipa"),
        ]:
            with patch("Tools.InstallerKit.installer_ci.publish_status") as status:
                with self.assertRaises((ValueError, OSError)):
                    installer_ci.complete(
                        request, path, self.feed, self.fetch, self.releases
                    )
                self.assertEqual(status.call_args.args[2].state, "failed")
        self.releases.publish.assert_not_called()

    def test_stale_source_never_uploads_or_updates_catalog(self):
        self.fetch.return_value = {**pull_request(), "labels": []}
        with patch("Tools.InstallerKit.installer_ci.publish_receipt") as publish:
            summary = installer_ci.complete(
                self.request, self.ipa, self.feed, self.fetch, self.releases
            )
        self.assertIn("Skipped", summary)
        publish.assert_not_called()
        self.releases.publish.assert_not_called()

    def test_preparing_requires_current_eligible_source(self):
        self.fetch.return_value = {**pull_request(), "state": "closed"}
        with self.assertRaises(ValueError):
            installer_ci.prepare(self.request, self.feed, self.fetch)
        self.feed.save.assert_not_called()

    def test_native_failure_command_never_reads_or_publishes_workspace_ipa(self):
        env = {
            f"INSTALLER_{key}": value
            for key, value in (
                ("REPOSITORY", self.request.repository),
                ("APP_ID", "where"),
                ("BUILD_SHA", self.request.sha),
                ("CHANNEL", "pr-42"),
                ("RUN", "12"),
                ("ATTEMPT", "2"),
                ("FEED_URL", self.request.feed_url),
            )
        }
        with (
            patch.dict(
                "os.environ",
                {
                    **env,
                    "GH_TOKEN": "secret",
                    "INSTALLER_WORKFLOW_URL": "https://app.circleci.com/pipelines/circleci/org/project/321",
                },
            ),
            patch(
                "Tools.InstallerKit.installer_ci.GitHubUpdateFeed",
                return_value=self.feed,
            ),
            patch("Tools.InstallerKit.installer_ci.publish_status") as status,
            patch("Tools.InstallerKit.installer_ci.complete") as complete,
        ):
            self.assertEqual(
                installer_ci.main(["fail", "--workspace", str(self.root / "missing")]),
                0,
            )
        complete.assert_not_called()
        self.assertEqual(status.call_args.args[2].state, "failed")

    def test_wrong_workspace_identity_fails_command_without_disclosing_secrets(self):
        env = {
            f"INSTALLER_{key}": value
            for key, value in (
                ("REPOSITORY", self.request.repository),
                ("APP_ID", "where"),
                ("BUILD_SHA", self.request.sha),
                ("CHANNEL", "pr-42"),
                ("RUN", "12"),
                ("ATTEMPT", "2"),
                ("FEED_URL", self.request.feed_url),
            )
        }
        (self.root / "request.json").write_text(json.dumps({"secret": "unexpected"}))
        with (
            patch.dict(
                "os.environ",
                {
                    **env,
                    "GH_TOKEN": "secret",
                    "INSTALLER_WORKFLOW_URL": "https://app.circleci.com/pipelines/circleci/org/project/321",
                },
            ),
            patch(
                "Tools.InstallerKit.installer_ci.GitHubUpdateFeed",
                return_value=self.feed,
            ),
            patch("Tools.InstallerKit.installer_ci.complete") as complete,
            patch("sys.stderr", new_callable=io.StringIO) as stderr,
        ):
            self.assertEqual(
                installer_ci.main(["finish", "--workspace", str(self.root)]), 1
            )
        complete.assert_not_called()
        self.assertNotIn("secret", stderr.getvalue())
