import contextlib
import io
import os
import unittest
from unittest.mock import patch

from Tools import ci_daily_audiences


class DailyWhereAudienceTests(unittest.TestCase):
    revision = "a" * 40
    scheduled = "11111111-1111-4111-8111-111111111111"
    prior = "22222222-2222-4222-8222-222222222222"
    workflow = "33333333-3333-4333-8333-333333333333"
    project = "circleci/organization/project"
    history = f"insights/{project}/workflows/Daily%20Where%20Audiences?branch=main"

    def setUp(self):
        self.values = {
            "pipeline.project.slug": self.project,
            "pipeline.event.name": "schedule",
            "pipeline.git.repo_url": "https://github.com/example/Stuff",
            "pipeline.git.branch": "main",
            "pipeline.git.revision": self.revision,
            "pipeline.config.repository.url": "https://github.com/example/Stuff",
            "pipeline.config.file_path": ".circleci/config.yml",
            "pipeline.config.ref": "refs/heads/main",
            "pipeline.config.sha": self.revision,
        }
        self.run = {
            "id": self.workflow,
            "status": "success",
            "created_at": "2026-11-22T06:00:00Z",
        }
        self.responses = {
            f"pipeline/{self.scheduled}/values": self.values,
            self.history: {"items": [self.run]},
            f"workflow/{self.workflow}": {
                "name": "Daily Where Audiences",
                "status": "success",
                "pipeline_id": self.prior,
                "project_slug": self.project,
            },
            f"pipeline/{self.prior}/values": self.values.copy(),
            f"workflow/{self.workflow}/job": {
                "items": [{"name": "Build Where Audiences", "status": "success"}]
            },
        }

    def command(self):
        output = io.StringIO()
        with (
            patch.dict(
                os.environ,
                {
                    "CIRCLE_PIPELINE_ID": self.scheduled,
                    "CI_CHECKOUT_SHA": self.revision,
                },
            ),
            patch.object(
                ci_daily_audiences,
                "public_circleci_get",
                side_effect=self.responses.__getitem__,
            ),
            contextlib.redirect_stdout(output),
            contextlib.redirect_stderr(output),
        ):
            code = ci_daily_audiences.main()
        return code, output.getvalue()

    def test_same_successful_daily_compile_skips_even_after_missed_days(self):
        code, message = self.command()
        self.assertEqual(code, 0)
        self.assertIn(f"https://app.circleci.com/workflow/{self.workflow}", message)

    def test_latest_failure_or_no_recent_run_builds(self):
        for history in (
            [],
            [
                self.run,
                {**self.run, "status": "failed", "created_at": "2026-11-23T06:00:00Z"},
            ],
        ):
            with self.subTest(history=history):
                self.responses[self.history] = {"items": history}
                self.assertEqual(self.command()[0], 1)

    def test_changed_checkout_untrusted_config_and_non_daily_events_build(self):
        for field, changed in (
            ("pipeline.git.revision", "b" * 40),
            ("pipeline.config.sha", "b" * 40),
            ("pipeline.config.ref", "refs/heads/other"),
            ("pipeline.config.file_path", ".circleci/experimental.yml"),
            ("pipeline.event.name", "pull_request"),
            ("pipeline.git.branch", "other"),
            ("pipeline.project.slug", "circleci/other/project"),
        ):
            with self.subTest(field=field):
                self.responses[f"pipeline/{self.prior}/values"] = {
                    **self.values,
                    field: changed,
                }
                self.assertEqual(self.command()[0], 1)

    def test_dummy_skipped_or_failed_job_cannot_establish_success(self):
        for job in (
            {"name": "Validation skipped", "status": "success"},
            {"name": "Build Where Audiences", "status": "not_run"},
            {"name": "Build Where Audiences", "status": "failed"},
        ):
            with self.subTest(job=job):
                self.responses[f"workflow/{self.workflow}/job"] = {"items": [job]}
                self.assertEqual(self.command()[0], 1)

    def test_incomplete_provider_evidence_builds(self):
        del self.responses[self.history]
        code, message = self.command()
        self.assertEqual(code, 1)
        self.assertIn("Building both audiences", message)
