import contextlib
import io
import json
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import HTTPError

from Tools import ci_circleci
from Tools.Tests.ci_test_support import GitRepository


class CICircleCITests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="CI continuation ü ")
        self.addCleanup(temporary.cleanup)
        self.repo = GitRepository(temporary.name)
        self.repo.write("README.md", "Revised docs\n")
        head = self.repo.commit()
        self.environment = {
            "CI_EVENT": "pull_request",
            "CI_BASE_SHA": self.repo.base,
            "CI_HEAD_SHA": head,
            "CIRCLE_CONTINUATION_KEY": "synthetic-secret",
        }

    def request(self, **environment):
        requests = []
        with contextlib.redirect_stderr(io.StringIO()):
            ci_circleci.continue_pipeline(
                self.repo.root, {**self.environment, **environment}, requests.append
            )
        self.assertEqual(len(requests), 1)
        request = requests[0]
        self.assertEqual(
            request.full_url, "https://circleci.com/api/v2/pipeline/continue"
        )
        self.assertEqual(request.method, "POST")
        self.assertEqual(request.get_header("Content-type"), "application/json")
        return json.loads(request.data)

    def test_documentation_continues_with_only_the_new_parameter(self):
        payload = self.request()
        self.assertEqual(payload["parameters"], {"docs_only": True})
        self.assertEqual(payload["configuration"], "version: 2.1\n")
        self.assertEqual(payload["continuation-key"], "synthetic-secret")

    def test_manual_main_and_publication_requests_keep_full_ci(self):
        for environment in (
            {"CI_MANUAL_FULL_GATE": "true"},
            {"CI_EVENT": "push"},
            {"CI_EVENT": "api"},
            {"CI_BASE_SHA": "<nil>"},
        ):
            with self.subTest(environment=environment):
                self.assertEqual(
                    self.request(**environment)["parameters"], {"docs_only": False}
                )

    def test_missing_key_or_configuration_never_posts(self):
        requests = []
        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(ValueError):
                ci_circleci.continue_pipeline(self.repo.root, {}, requests.append)
            (self.repo.root / ".circleci/continue.yml").unlink()
            with self.assertRaises(FileNotFoundError):
                ci_circleci.continue_pipeline(
                    self.repo.root, self.environment, requests.append
                )
        self.assertEqual(requests, [])

    def test_command_failure_is_nonzero_and_never_discloses_transport_data(self):
        errors = (
            HTTPError("https://circleci.com", 403, "synthetic-secret", {}, None),
            OSError("synthetic-secret"),
            ValueError("synthetic-secret"),
        )
        for error in errors:
            with self.subTest(error=type(error).__name__):
                stdout, stderr = io.StringIO(), io.StringIO()
                with (
                    patch.object(
                        ci_circleci, "repository_root", return_value=self.repo.root
                    ),
                    patch.dict(ci_circleci.os.environ, self.environment, clear=True),
                    patch.object(ci_circleci, "request_json", side_effect=error),
                    contextlib.redirect_stdout(stdout),
                    contextlib.redirect_stderr(stderr),
                ):
                    status = ci_circleci.main()
                self.assertEqual(status, 1)
                self.assertEqual(stdout.getvalue(), "")
                self.assertIn("continuation failed", stderr.getvalue())
                self.assertNotIn("synthetic-secret", stderr.getvalue())

    def test_command_reports_success_only_after_continuation(self):
        stdout, stderr = io.StringIO(), io.StringIO()
        with (
            patch.object(ci_circleci, "repository_root", return_value=self.repo.root),
            patch.dict(ci_circleci.os.environ, self.environment, clear=True),
            patch.object(ci_circleci, "request_json", return_value={}) as transport,
            contextlib.redirect_stdout(stdout),
            contextlib.redirect_stderr(stderr),
        ):
            status = ci_circleci.main()
        self.assertEqual(status, 0)
        self.assertEqual(transport.call_count, 1)
        self.assertEqual(stdout.getvalue(), "CircleCI pipeline continued.\n")
        self.assertNotIn("synthetic-secret", stderr.getvalue())
