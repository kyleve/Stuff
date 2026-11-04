import io
from http.client import BadStatusLine
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch
from urllib.error import HTTPError

from Tools.flyover_distribution import CaptureRequest, download, main, publish
from Tools.Tests.flyover_bundle_support import SHA
from Tools.circleci_pipeline import CircleCI, wait_for_archive
from Fixtures.circleci_distribution_fixtures import (
    ARTIFACT_URL,
    DEFINITION,
    PIPELINE,
    PROJECT,
    CircleCIServer,
)


class FlyoverDistributionTests(unittest.TestCase):
    def test_command_recovers_from_discovery_404_and_times_out_without_publication(
        self,
    ):
        for recovers in (True, False):
            with self.subTest(recovers=recovers):
                server = CircleCIServer()
                server.workflows[0]["name"] = "Flyover Export"
                server.jobs[0]["name"] = "Export Flyover"
                server.artifacts[0]["path"] = "flyover/atlases.zip"
                lookups = 0

                def transport(request):
                    nonlocal lookups
                    if request.full_url.endswith(f"pipeline/{PIPELINE}"):
                        lookups += 1
                        if lookups == 1 or not recovers:
                            raise HTTPError(
                                request.full_url, 404, "secret", {}, io.BytesIO()
                            )
                    return server(request)

                client = CircleCI(
                    PROJECT,
                    "token",
                    transport,
                    workflow="Flyover Export",
                    job="Export Flyover",
                    artifact="flyover/atlases.zip",
                )
                ticks = iter([0, 0, 15, 30])

                def wait(client, pipeline):
                    return wait_for_archive(
                        client,
                        pipeline,
                        timeout=30,
                        clock=lambda: next(ticks),
                        sleep=lambda _: None,
                    )

                environment = {
                    "CIRCLECI_PROJECT": PROJECT,
                    "CIRCLECI_PIPELINE": DEFINITION,
                    "CIRCLECI_TOKEN": "token",
                    "GITHUB_REPOSITORY": "owner/repo",
                    "GITHUB_RUN_ID": "10",
                    "GITHUB_RUN_ATTEMPT": "1",
                }
                with (
                    patch.dict("os.environ", environment),
                    patch("Tools.flyover_distribution.CircleCI", return_value=client),
                    patch(
                        "Tools.flyover_distribution.wait_for_archive", side_effect=wait
                    ),
                    patch("Tools.flyover_distribution.download") as download,
                    patch("Tools.flyover_distribution.unpack_bundle") as validate,
                    patch("Tools.flyover_distribution.subprocess.run") as run,
                    patch("sys.stdout", new_callable=io.StringIO) as stdout,
                    patch("sys.stderr", new_callable=io.StringIO) as stderr,
                ):
                    self.assertEqual(main(["--sha", SHA]), 0 if recovers else 1)
                self.assertEqual(lookups, 2)
                self.assertEqual(
                    sum(request.method == "POST" for request in server.requests), 1
                )
                self.assertIn(PIPELINE, stdout.getvalue())
                self.assertNotIn("secret", stderr.getvalue())
                if recovers:
                    self.assertEqual(stderr.getvalue(), "")
                    self.assertEqual(download.call_args.args[0], ARTIFACT_URL)
                    validate.assert_called_once()
                    self.assertEqual(run.call_count, 3)
                    self.assertEqual(
                        run.call_args.args[0][1:4],
                        ["workflow", "run", "installer-pages.yml"],
                    )
                else:
                    self.assertIn("publication did not complete", stderr.getvalue())
                    download.assert_not_called()
                    validate.assert_not_called()
                    run.assert_not_called()

    def test_malformed_header_never_prints_token_or_traceback(self):
        environment = {
            "CIRCLECI_PROJECT": "gh/owner/repo",
            "CIRCLECI_PIPELINE": "11111111-1111-1111-1111-111111111111",
            "GITHUB_REPOSITORY": "owner/repo",
            "GITHUB_RUN_ID": "1",
            "GITHUB_RUN_ATTEMPT": "1",
            "CIRCLECI_TOKEN": "FAKE_ONLY\nSECOND_LINE",
        }
        with (
            patch.dict("os.environ", environment),
            patch("sys.stderr", new_callable=io.StringIO) as output,
            patch(
                "http.client.HTTPSConnection.connect",
                side_effect=AssertionError("network forbidden"),
            ) as connect,
        ):
            self.assertEqual(main(["--sha", SHA]), 1)
        connect.assert_not_called()
        self.assertEqual(
            output.getvalue(),
            "flyover publication: ValueError; publication did not complete\n",
        )

    def test_error_messages_never_echo_exception_payloads(self):
        environment = {
            key: "test"
            for key in (
                "CIRCLECI_PROJECT",
                "CIRCLECI_PIPELINE",
                "GITHUB_REPOSITORY",
                "GITHUB_RUN_ID",
                "GITHUB_RUN_ATTEMPT",
            )
        }
        for error in (
            ValueError("Authorization: secret"),
            BadStatusLine("secret"),
            OSError("secret"),
        ):
            with (
                self.subTest(error=type(error).__name__),
                patch.dict("os.environ", environment),
                patch("sys.stderr", new_callable=io.StringIO) as output,
                patch("Tools.flyover_distribution.publish", side_effect=error),
            ):
                self.assertEqual(main(["--sha", SHA]), 1)
                self.assertNotIn("secret", output.getvalue())
                self.assertIn(type(error).__name__, output.getvalue())

    def test_controller_errors_do_not_log_signed_urls(self):
        environment = {
            key: "test"
            for key in (
                "CIRCLECI_PROJECT",
                "CIRCLECI_PIPELINE",
                "GITHUB_REPOSITORY",
                "GITHUB_RUN_ID",
                "GITHUB_RUN_ATTEMPT",
            )
        }
        with (
            patch.dict("os.environ", environment),
            patch("sys.stderr", new_callable=io.StringIO) as output,
            patch(
                "Tools.flyover_distribution.publish",
                side_effect=HTTPError("https://host/secret", 403, "secret", {}, None),
            ),
        ):
            self.assertEqual(main(["--sha", SHA]), 1)
        self.assertIn("HTTP 403", output.getvalue())
        self.assertNotIn("secret", output.getvalue())

    def test_failed_upload_never_publishes_or_dispatches(self):
        import subprocess

        with (
            patch.dict("os.environ", {"CIRCLECI_TOKEN": "token"}),
            patch("Tools.flyover_distribution.CircleCI"),
            patch("Tools.flyover_distribution.wait_for_archive", return_value="url"),
            patch("Tools.flyover_distribution.download"),
            patch("Tools.flyover_distribution.unpack_bundle"),
            patch(
                "Tools.flyover_distribution.subprocess.run",
                side_effect=subprocess.CalledProcessError(1, "gh"),
            ) as run,
        ):
            with self.assertRaises(subprocess.CalledProcessError):
                publish("project", "definition", "owner/repo", SHA, "10", "1")
            self.assertEqual(run.call_count, 1)

    def test_request_only_enables_unsigned_flyover_workflow(self):
        self.assertEqual(
            CaptureRequest(SHA).parameters,
            {"flyover_export": "true", "flyover_sha": SHA},
        )
        with self.assertRaises(ValueError):
            CaptureRequest("main")

    def test_release_is_published_only_after_validation_and_upload(self):
        events = []
        client = Mock(token="token")
        with (
            patch.dict("os.environ", {"CIRCLECI_TOKEN": "token"}),
            patch("Tools.flyover_distribution.CircleCI", return_value=client),
            patch("Tools.flyover_distribution.wait_for_archive", return_value="url"),
            patch(
                "Tools.flyover_distribution.download",
                side_effect=lambda *args: events.append("download"),
            ),
            patch(
                "Tools.flyover_distribution.unpack_bundle",
                side_effect=lambda *args: events.append("validate"),
            ),
            patch(
                "Tools.flyover_distribution.subprocess.run",
                side_effect=lambda argv, **kwargs: events.append(argv),
            ),
        ):
            publish("project", "definition", "owner/repo", SHA, "10", "2")
        self.assertEqual(events[:2], ["download", "validate"])
        self.assertIn("--draft", events[2])
        self.assertEqual(events[3][-1], "--draft=false")
        self.assertEqual(events[4][1:4], ["workflow", "run", "installer-pages.yml"])

    def test_failed_capture_validation_never_creates_a_release(self):
        with (
            patch.dict("os.environ", {"CIRCLECI_TOKEN": "token"}),
            patch("Tools.flyover_distribution.CircleCI"),
            patch("Tools.flyover_distribution.wait_for_archive", return_value="url"),
            patch("Tools.flyover_distribution.download"),
            patch(
                "Tools.flyover_distribution.unpack_bundle",
                side_effect=ValueError("invalid"),
            ),
            patch("Tools.flyover_distribution.subprocess.run") as run,
        ):
            with self.assertRaises(ValueError):
                publish("project", "definition", "owner/repo", SHA, "10", "1")
            run.assert_not_called()

    def test_download_is_bounded_and_does_not_redirect_credentials(self):
        with (
            tempfile.TemporaryDirectory() as temporary,
            patch("Tools.flyover_distribution.build_opener") as opener,
            patch("Tools.flyover_distribution.MAX_BYTES", 2),
        ):
            opener.return_value.open.return_value = io.BytesIO(b"123")
            with self.assertRaisesRegex(ValueError, "size budget"):
                download(
                    "https://output.circle-artifacts.com/atlas",
                    Path(temporary) / "atlas.zip",
                    "token",
                )
            request = opener.return_value.open.call_args.args[0]
            self.assertEqual(request.headers, {})
            self.assertEqual(request.get_header("Circle-token"), "token")
