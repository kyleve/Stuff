import copy
import unittest
from unittest.mock import Mock

from Tools.ci_actions_evidence import validated_actions_run


class ActionsEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.head = "a" * 40
        self.tree = "b" * 40
        self.run = {
            "id": 123,
            "run_attempt": 2,
            "path": ".github/workflows/ci.yml",
            "event": "pull_request",
            "status": "completed",
            "conclusion": "success",
            "head_sha": self.head,
            "pull_requests": [],
            "repository": {"id": 3, "full_name": "owner/repo"},
            "head_repository": {"id": 3},
        }
        self.marker = f"Check agent guidance for PR #42 on tree {self.tree}"
        self.config = {"classifier": "Inspect", "workers": ["Compile", "Test"]}
        self.jobs = {
            name: {
                "name": name,
                "status": "completed",
                "conclusion": "success",
                "run_id": 123,
                "run_attempt": 2,
                "head_sha": self.head,
                "steps": [],
            }
            for name in ("Inspect", "Compile", "Test")
        }
        self.jobs["Inspect"]["steps"].append(
            {"name": self.marker, "status": "completed", "conclusion": "success"}
        )

    def select(self, run=None, jobs=None, total_count=None, config=None):
        jobs = list(self.jobs.values()) if jobs is None else jobs
        self.get = Mock(
            side_effect=[
                {"workflow_runs": [self.run if run is None else run]},
                {
                    "total_count": len(jobs) if total_count is None else total_count,
                    "jobs": jobs,
                },
            ]
        )
        return validated_actions_run(
            self.get,
            42,
            self.head,
            self.tree,
            self.config if config is None else config,
        )

    def test_uses_actual_checkout_tree_even_after_pr_association_disappears(self):
        self.assertEqual(
            self.select(), "https://github.com/owner/repo/actions/runs/123/attempts/2"
        )
        self.assertEqual(
            [call.args[0] for call in self.get.call_args_list],
            [
                f"actions/workflows/ci.yml/runs?event=pull_request&head_sha={self.head}&per_page=1",
                "actions/runs/123/attempts/2/jobs?per_page=100",
            ],
        )

    def test_requires_successful_same_repository_ci_pull_request_run(self):
        for overrides in (
            {"event": "push"},
            {"path": ".github/workflows/custom.yml"},
            {"head_sha": self.tree},
            {"head_repository": {"id": 4}},
            {"status": "in_progress"},
            {"conclusion": "cancelled"},
            {"pull_requests": [{"number": 41, "head": {"sha": self.head}}]},
        ):
            with self.subTest(overrides=overrides):
                self.assertIsNone(self.select(run={**self.run, **overrides}))
                self.assertEqual(self.get.call_count, 1)

    def test_rejects_skipped_missing_or_mixed_attempt_jobs(self):
        remaining = [job for job in self.jobs.values() if job["name"] != "Test"]
        self.assertIsNone(self.select(jobs=remaining))
        self.assertIsNone(self.select(jobs=remaining + [remaining[0]]))
        self.assertIsNone(self.select(total_count=len(self.jobs) + 1))
        for changes in (
            {"conclusion": "skipped"},
            {"status": "queued"},
            {"run_attempt": 1},
            {"run_id": 124},
            {"head_sha": self.tree},
        ):
            with self.subTest(changes=changes):
                self.assertIsNone(
                    self.select(jobs=remaining + [{**self.jobs["Test"], **changes}])
                )

    def test_requires_configured_worker_set_and_classifier_role(self):
        for config in (
            {"classifier": "Inspect", "workers": ["Compile"]},
            {"classifier": "Inspect", "workers": ["Compile", "Publish"]},
            {"classifier": "Compile", "workers": ["Inspect", "Test"]},
        ):
            with self.subTest(config=config):
                self.assertIsNone(self.select(config=config))

    def test_only_completed_classifier_step_can_attest_pr_and_tree(self):
        for marker in (
            None,
            self.marker.replace("#42", "#24"),
            self.marker.replace(self.tree, self.head),
            self.marker + " suffix",
        ):
            with self.subTest(marker=marker):
                jobs = copy.deepcopy(self.jobs)
                steps = jobs["Inspect"]["steps"]
                jobs["Compile"]["steps"] = copy.deepcopy(steps)
                if marker:
                    steps[0]["name"] = marker
                else:
                    steps[0]["conclusion"] = "skipped"
                self.assertIsNone(self.select(jobs=list(jobs.values())))
