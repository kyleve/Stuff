import io
import json
import unittest
from unittest.mock import patch

from Tools import ci_request

REGISTRATION = {
    "repository": "kyleve/Stuff",
    "project": "circleci/org/project",
    "definition": "5f599fdc-99d4-4954-9200-c7575bbcbf75",
}


class CIRequestTests(unittest.TestCase):
    def test_publication_uses_fixed_definition_and_main_both_sources(self):
        args = ci_request.request_arguments(
            "kyleve/Stuff", "installer", 42, "main", REGISTRATION
        )
        self.assertEqual(
            args[:3],
            ["circleci", "api", "api/v2/project/circleci/org/project/pipeline/run"],
        )
        payload = json.loads(args[-1])
        self.assertEqual(payload["definition_id"], REGISTRATION["definition"])
        self.assertEqual(payload["config"], {"branch": "main"})
        self.assertEqual(payload["checkout"], {"branch": "main"})
        self.assertEqual(
            payload["parameters"], {"publication_task": "installer", "pull_request": 42}
        )

    def test_manual_gate_targets_an_explicit_stack_tip(self):
        payload = json.loads(
            ci_request.request_arguments(
                "kyleve/Stuff", "ci", 0, "codex/topic", REGISTRATION
            )[-1]
        )
        self.assertEqual(payload["config"], {"branch": "codex/topic"})
        self.assertEqual(payload["parameters"], {"manual_full_gate": "true"})

    def test_invalid_requests_fail_before_invoking_circleci(self):
        for task, number, branch in [
            ("installer", 42, "untrusted"),
            ("pages", 42, "main"),
            ("installer", -1, "main"),
            ("unknown", 0, "main"),
        ]:
            with self.assertRaises(ValueError):
                ci_request.request_arguments(
                    "kyleve/Stuff", task, number, branch, REGISTRATION
                )
        with self.assertRaises(ValueError):
            ci_request.settings("fork/Stuff")

    def test_enable_app_uses_circle_project_variable(self):
        payload = json.loads(
            ci_request.enable_arguments("kyleve/Stuff", "throw", REGISTRATION)[-1]
        )
        self.assertEqual(
            payload, {"name": "THROW_DISTRIBUTION_ENABLED", "value": "true"}
        )

    def test_command_reports_failure_without_credentials_or_response_body(self):
        with (
            patch("Tools.ci_request.subprocess.run", side_effect=OSError("secret")),
            patch("sys.stderr", new_callable=io.StringIO) as stderr,
        ):
            self.assertEqual(ci_request.main(["pages"]), 1)
        self.assertNotIn("secret", stderr.getvalue())
