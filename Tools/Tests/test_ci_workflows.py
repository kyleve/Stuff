"""Guard required checks and the boundary before expensive runner allocation."""

import json
import subprocess
import unittest

from Tools.repository import repository_root


class CIWorkflowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = repository_root(__file__)
        cls.github, cls.setup, cls.continued = json.loads(
            subprocess.check_output(
                [
                    "ruby",
                    "-ryaml",
                    "-rjson",
                    "-e",
                    "puts JSON.generate(ARGV.map { |path| YAML.load_file(path) })",
                    str(root / ".github/workflows/ci.yml"),
                    str(root / ".circleci/config.yml"),
                    str(root / ".circleci/continue.yml"),
                ],
                text=True,
            )
        )

    def test_github_keeps_workflow_triggers_and_required_job_names(self):
        triggers = self.github.get("on", self.github.get("true"))
        self.assertEqual(set(triggers), {"push", "pull_request", "workflow_dispatch"})
        self.assertEqual(triggers["pull_request"], {"branches": ["main"]})
        self.assertEqual(triggers["push"], {"branches": ["main"]})
        jobs = self.github["jobs"]
        self.assertEqual(
            {value["name"] for key, value in jobs.items() if key != "changes"},
            {
                "Lint & Formatting",
                "Tool Tests",
                "Web Checks & Tests",
                "Bumper Bowling",
                "Build & Test (macOS)",
            },
        )

    def test_every_github_worker_uses_the_same_fail_safe_selection(self):
        jobs = self.github["jobs"]
        for key, job in jobs.items():
            if key == "changes":
                continue
            with self.subTest(job=key):
                self.assertEqual(job["needs"], "changes")
                self.assertIn("!cancelled()", job["if"])
                self.assertIn("needs.changes.result != 'success'", job["if"])
                self.assertIn("needs.changes.outputs.docs_only != 'true'", job["if"])
                self.assertIn(
                    "!contains(github.event.pull_request.title, 'NO-CI')", job["if"]
                )
        classifier = jobs["changes"]
        self.assertEqual(classifier["runs-on"], "ubuntu-latest")
        self.assertEqual(classifier["steps"][0]["with"]["fetch-depth"], 0)
        command = classifier["steps"][1]
        self.assertIn("Tools.ci_changes", command["run"])
        self.assertEqual(
            command["env"]["CI_HEAD_SHA"], "${{ github.event.pull_request.head.sha }}"
        )
        self.assertEqual(
            command["env"]["CI_BASE_SHA"], "${{ github.event.pull_request.base.sha }}"
        )

    def test_circleci_continues_once_and_inherits_original_parameters(self):
        self.assertTrue(self.setup["setup"])
        self.assertNotIn("setup", self.continued)
        self.assertEqual(len(self.setup["workflows"]), 1)
        parameters = dict(self.continued["parameters"])
        self.assertEqual(
            parameters.pop("docs_only"), {"type": "boolean", "default": False}
        )
        self.assertEqual(parameters, self.setup["parameters"])
        job = self.setup["jobs"]["select-workflows"]
        self.assertIn("docker", job)
        self.assertNotIn("context", job)
        self.assertIn("Tools.ci_circleci", job["steps"][-1]["run"]["command"])
        for key, suffix in (("CI_BASE_SHA", "base.sha"), ("CI_HEAD_SHA", "head.sha")):
            self.assertEqual(
                job["environment"][key],
                f"<< pipeline.event.github.pull_request.{suffix} >>",
            )

    def test_circleci_docs_workflow_completes_without_any_macos_job(self):
        workflow = self.continued["workflows"]["iOS CI"]
        self.assertIn(
            'pipeline.parameters.manual_full_gate == "true"', workflow["when"]
        )
        self.assertIn('pipeline.git.branch == "main"', workflow["when"])
        self.assertIn("NO-CI", workflow["when"])
        for item in workflow["jobs"]:
            name, options = next(iter(item.items()))
            with self.subTest(job=name):
                if name == "documentation-only":
                    self.assertEqual(
                        options["filters"], "pipeline.parameters.docs_only"
                    )
                else:
                    self.assertEqual(
                        options["filters"], "not pipeline.parameters.docs_only"
                    )
        job = self.continued["jobs"]["documentation-only"]
        self.assertIn("docker", self.continued["executors"][job["executor"]])
        self.assertEqual(len(job["steps"]), 1)
        self.assertIn("echo", job["steps"][0]["run"])

    def test_publication_workflows_remain_separate_from_documentation_selection(self):
        for name in ("Flyover Export", "Installer Archive"):
            workflow = self.continued["workflows"][name]
            self.assertNotIn("docs_only", json.dumps(workflow))
            self.assertIn('pipeline.event.name == "api"', workflow["when"])
            self.assertIn('pipeline.config.ref == "refs/heads/main"', workflow["when"])
        archive = self.continued["workflows"]["Installer Archive"]["jobs"][0]
        self.assertEqual(
            archive["archive-app"]["context"], "where-distribution-signing"
        )
