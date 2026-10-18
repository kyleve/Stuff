from contextlib import redirect_stderr
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import zipfile
from unittest.mock import Mock, patch
from urllib.request import Request

from Tools.InstallerKit.circleci_distribution import ArtifactRedirects, CircleCI, artifact_url, download_ipa, main, wait_for_archive
from Tools.repository import repository_root
from Fixtures.circleci_distribution_fixtures import ARTIFACT_URL, DEFINITION, PIPELINE, PROJECT, CircleCIServer, archive_request, write_archive


class CircleCIDistributionTests(unittest.TestCase):
    def setUp(self):
        self.server = CircleCIServer()
        self.client = CircleCI(PROJECT, "fixture-api-token", self.server)

    def test_trigger_uses_trusted_main_and_passes_only_build_metadata(self):
        request = archive_request()
        self.assertEqual(self.client.start(DEFINITION, request), PIPELINE)
        call = self.server.requests[0]
        self.assertEqual(json.loads(call.data), {"definition_id": DEFINITION, "config": {"branch": "main"},
                                               "checkout": {"branch": "main"}, "parameters": request.parameters})
        self.assertEqual(call.get_header("Circle-token"), "fixture-api-token")
        self.assertNotIn(b"fixture-api-token", call.data)

    def test_only_the_successful_pipeline_job_supplies_the_archive(self):
        self.assertEqual(self.client.artifact(PIPELINE), ARTIFACT_URL)
        self.assertTrue(all(call.host == "circleci.com" for call in self.server.requests))

    def test_failed_cancelled_and_unauthorized_workflows_never_fetch_artifacts(self):
        for status in ("failed", "canceled", "unauthorized", "error", "not_run"):
            with self.subTest(status=status):
                self.server.workflows[0]["status"] = status
                self.server.requests.clear()
                with self.assertRaisesRegex(ValueError, status):
                    self.client.artifact(PIPELINE)
                self.assertFalse(any(call.full_url.endswith("/artifacts") for call in self.server.requests))

    def test_wrong_project_configuration_and_ambiguous_workflows_fail_closed(self):
        for changes in ({"project_slug": "other/project"}, {"errors": [{"message": "invalid config"}]}):
            with self.subTest(changes=changes):
                server = CircleCIServer()
                server.pipeline.update(changes)
                with self.assertRaises(ValueError):
                    CircleCI(PROJECT, "token", server).artifact(PIPELINE)
        self.server.workflows *= 2
        with self.assertRaisesRegex(ValueError, "ambiguous"):
            self.client.artifact(PIPELINE)

    def test_missing_wrong_and_duplicate_artifacts_are_rejected(self):
        original = self.server.artifacts[0]
        for artifacts in ([], [{**original, "path": "other/Where.ipa"}], [original, original],
                          [{**original, "url": "https://evil.example/app.ipa"}]):
            with self.subTest(artifacts=artifacts):
                self.server.artifacts = artifacts
                with self.assertRaises(ValueError):
                    self.client.artifact(PIPELINE)

    def test_polling_waits_for_completion_and_has_a_deadline(self):
        client = Mock()
        client.artifact.side_effect = [None, ARTIFACT_URL]
        sleep = Mock()
        self.assertEqual(wait_for_archive(client, PIPELINE, clock=lambda: 0, sleep=sleep), ARTIFACT_URL)
        sleep.assert_called_once_with(15)
        ticks = iter([0, 0, 16])
        client.artifact.side_effect = None
        client.artifact.return_value = None
        with self.assertRaisesRegex(ValueError, "timed out"):
            wait_for_archive(client, PIPELINE, timeout=15, clock=lambda: next(ticks), sleep=Mock())

    def test_pagination_escapes_tokens_and_detects_repeated_pages(self):
        transport = Mock(side_effect=[{"items": [1], "next_page_token": "a/b?c"}, {"items": [2]}])
        self.assertEqual(CircleCI(PROJECT, "token", transport).items("fixture"), [1, 2])
        self.assertTrue(transport.call_args.args[0].full_url.endswith("?page-token=a%2Fb%3Fc"))
        transport = Mock(return_value={"items": [], "next_page_token": "repeated"})
        with self.assertRaisesRegex(ValueError, "repeated"):
            CircleCI(PROJECT, "token", transport).items("fixture")

    def test_download_authenticates_only_to_circleci_and_validates_before_publication(self):
        with tempfile.TemporaryDirectory(prefix="archive ü ") as temporary:
            root = Path(temporary)
            fixture = root / "fixture.ipa"
            write_archive(fixture)
            with patch("Tools.InstallerKit.circleci_distribution.build_opener") as opener:
                opener.return_value.open.return_value = io.BytesIO(fixture.read_bytes())
                download_ipa(ARTIFACT_URL, root / "output/Where.ipa", archive_request(), "fixture-token")
                request = opener.return_value.open.call_args.args[0]
                self.assertEqual(request.get_header("Circle-token"), "fixture-token")
                redirected = ArtifactRedirects().redirect_request(
                    request, None, 302, "", {}, "https://bucket.s3.amazonaws.com/archive?signature=fixture")
                self.assertEqual(redirected.header_items(), [])
            self.assertEqual((root / "output/Where.ipa").read_bytes(), fixture.read_bytes())

    def test_bad_or_oversized_download_leaves_no_partial_archive(self):
        for contents in (b"not an IPA", b"x" * 21):
            with self.subTest(contents=contents), tempfile.TemporaryDirectory() as temporary:
                destination = Path(temporary) / "Where.ipa"
                with patch("Tools.InstallerKit.circleci_distribution.build_opener") as opener, \
                        patch("Tools.InstallerKit.circleci_distribution.MAX_IPA_BYTES", 20):
                    opener.return_value.open.return_value = io.BytesIO(contents)
                    with self.assertRaises((ValueError, zipfile.BadZipFile)):
                        download_ipa(ARTIFACT_URL, destination, archive_request(), "fixture-token")
                self.assertEqual(list(Path(temporary).iterdir()), [])

    def test_artifact_urls_and_redirects_reject_http_and_unrelated_hosts(self):
        for url in ("http://output.circle-artifacts.com/file", "https://circle-artifacts.com.evil.example/file",
                    "https://token@output.circle-artifacts.com/file", "https://api.github.com/file"):
            with self.subTest(url=url), self.assertRaises(ValueError):
                artifact_url(url)
        with self.assertRaises(ValueError):
            ArtifactRedirects().redirect_request(Request(ARTIFACT_URL), None, 302, "", {}, "http://127.0.0.1/file")

    def test_public_command_help_needs_no_credentials_from_an_unrelated_directory(self):
        with tempfile.TemporaryDirectory(prefix="help ü ") as temporary:
            result = subprocess.run([sys.executable, "-m", "Tools.InstallerKit.circleci_distribution", "--help"],
                                    cwd=temporary, env={"PATH": "/usr/bin:/bin", "PYTHONPATH": str(repository_root(__file__)),
                                                        "PYTHONDONTWRITEBYTECODE": "1"}, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("--definition", result.stdout)

    def test_command_rejects_missing_token_before_network_or_output(self):
        request = archive_request()
        with tempfile.TemporaryDirectory() as temporary, patch.dict("os.environ", {}, clear=True), \
                redirect_stderr(io.StringIO()) as stderr, patch("Tools.InstallerKit.circleci_distribution.CircleCI.start") as start:
            output = Path(temporary) / "Where.ipa"
            self.assertEqual(main(["--project", PROJECT, "--definition", DEFINITION, "--repository", request.repository,
                                   "--app", request.app_id, "--sha", request.sha, "--channel", request.channel,
                                   "--run", request.run, "--attempt", request.attempt, "--feed-url", request.feed_url,
                                   "--output", str(output)]), 1)
            self.assertIn("API token", stderr.getvalue())
            start.assert_not_called()
            self.assertFalse(output.exists())
