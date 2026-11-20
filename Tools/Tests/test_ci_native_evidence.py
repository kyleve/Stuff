import unittest
from unittest.mock import Mock

from Tools.ci_native_evidence import validated_native_run


HEAD = "a" * 40
WORKFLOW = "https://app.circleci.com/workflow/445a225a-8ba2-4e89-8aba-04ae1698d77e"
PIPELINE = "8883c1e8-657c-4bc6-8562-50510a52b8b6"
CONFIG = {"workflow": "Device validation", "jobs": ["Compile", "Run tests"]}


class NativeEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.statuses = [
            {
                "context": f"ci/circleci: {job}",
                "state": "success",
                "creator": {"id": 127350680, "login": "circleci-app[bot]"},
                "target_url": f"{WORKFLOW}/job/0992afbb-abdb-459b-b528-{index:012x}",
            }
            for index, job in enumerate(CONFIG["jobs"], 1)
        ]
        self.workflow = {
            "id": WORKFLOW.rsplit("/", 1)[1],
            "status": "success",
            "name": CONFIG["workflow"],
            "pipeline_id": PIPELINE,
        }
        self.values = {
            "pipeline.id": PIPELINE,
            "pipeline.project.git_url": "https://github.com/kyleve/Stuff",
            "pipeline.git.repo_url": "https://github.com/kyleve/Stuff",
            "pipeline.git.revision": HEAD,
            "pipeline.config.repository.url": "https://github.com/kyleve/Stuff",
            "pipeline.config.file_path": ".circleci/config.yml",
            "pipeline.config.sha": HEAD,
            "pipeline.event.name": "pull_request",
            "pipeline.event.github.pull_request.base.ref": "main",
            "pipeline.event.github.pull_request.head.sha": HEAD,
            "pipeline.event.github.pull_request.number": 542,
        }

    def evidence(self, statuses, *, config=CONFIG, workflow=None, values=None):
        get = Mock(return_value=statuses)
        circle = {
            f"workflow/{self.workflow['id']}": self.workflow
            if workflow is None
            else workflow,
            f"pipeline/{PIPELINE}/values": self.values if values is None else values,
        }
        result = validated_native_run(
            get, HEAD, "kyleve/Stuff", 542, config, circle_get=circle.__getitem__
        )
        get.assert_called_once_with(f"commits/{HEAD}/statuses?per_page=100")
        return result

    def test_latest_successes_all_belong_to_the_proven_pr_workflow(self):
        older_pending = {**self.statuses[0], "state": "pending"}
        self.assertEqual(self.evidence([*self.statuses, older_pending]), WORKFLOW)

    def test_documentation_only_or_partial_pr_run_has_no_proof(self):
        for missing in range(len(self.statuses)):
            with self.subTest(missing=missing):
                remaining = self.statuses[:missing] + self.statuses[missing + 1 :]
                self.assertIsNone(self.evidence(remaining))

    def test_empty_or_duplicate_configured_jobs_cannot_prove_workflow(self):
        for jobs in [[], ["Compile", "Compile"]]:
            with self.subTest(jobs=jobs):
                self.assertIsNone(
                    self.evidence(self.statuses, config={**CONFIG, "jobs": jobs})
                )

    def test_newer_failure_pending_or_untrusted_status_supersedes_success(self):
        for changed in [
            {"state": "failure"},
            {"state": "pending"},
            {"creator": {"id": 123, "login": "circleci-app[bot]"}},
            {"creator": None},
        ]:
            with self.subTest(changed=changed):
                statuses = [{**self.statuses[0], **changed}, *self.statuses]
                self.assertIsNone(self.evidence(statuses))

    def test_later_rerun_mixed_jobs_or_unexpected_target_cannot_prove_workflow(self):
        url = self.statuses[0]["target_url"]
        for changed_url in [
            url.replace("445a225a", "545a225a"),
            self.statuses[1]["target_url"],
            url.replace("app.circleci.com", "example.com"),
            url.replace("/workflow/", "/different-path/"),
            url + "/unexpected",
            None,
        ]:
            with self.subTest(changed_url=changed_url):
                statuses = [
                    {**self.statuses[0], "target_url": changed_url},
                    *self.statuses,
                ]
                self.assertIsNone(self.evidence(statuses))

    def test_requires_the_successful_native_workflow(self):
        for changed in [
            {"status": "running"},
            {"status": "failed"},
            {"id": PIPELINE},
            {"name": "Installer Archive"},
            {"pipeline_id": "../../other"},
        ]:
            with self.subTest(changed=changed):
                self.assertIsNone(
                    self.evidence(self.statuses, workflow={**self.workflow, **changed})
                )

    def test_manual_other_pr_and_unmatched_checkout_or_config_are_ineligible(self):
        for changed in [
            {"pipeline.id": "unknown"},
            {"pipeline.event.name": "api"},
            {"pipeline.event.name": "push"},
            {"pipeline.event.github.pull_request.number": 543},
            {"pipeline.event.github.pull_request.base.ref": "stacked"},
            {"pipeline.event.github.pull_request.head.sha": "b" * 40},
            {"pipeline.project.git_url": "https://github.com/another/Stuff"},
            {"pipeline.git.repo_url": "https://github.com/another/Stuff"},
            {"pipeline.git.revision": "b" * 40},
            {"pipeline.config.sha": "b" * 40},
            {"pipeline.config.repository.url": "https://github.com/another/Stuff"},
            {"pipeline.config.file_path": ".circleci/other.yml"},
        ]:
            with self.subTest(changed=changed):
                self.assertIsNone(
                    self.evidence(self.statuses, values={**self.values, **changed})
                )
