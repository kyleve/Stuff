"""Guard required checks and the boundary before expensive runner allocation."""

import ast
import json
import re
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

    def test_guidance_is_checked_before_docs_skip_and_again_in_required_lint(self):
        jobs = self.github["jobs"]
        classifier = jobs["changes"]
        checkout = classifier["steps"][0]["with"]
        self.assertNotIn("sparse-checkout", checkout)
        self.assertFalse(checkout["lfs"])
        self.assertEqual(self.github["env"]["MISE_NO_HOOKS"], "1")
        setup = next(
            step
            for step in classifier["steps"]
            if step.get("uses") == "jdx/mise-action@v3"
        )
        self.assertEqual(setup["with"]["install_args"], "ruby")
        for job in (classifier, jobs["format"]):
            check = next(
                step
                for step in job["steps"]
                if step.get("name") == "Agent guidance check"
            )
            self.assertEqual(check["run"], "mise exec ruby -- ./sync-agents --check")
            self.assertNotIn("if", check)
            self.assertNotIn("continue-on-error", check)
            self.assertNotIn("continue-on-error", job)
        self.assertNotIn("docs_only", classifier["if"])
        self.assertIn("needs.changes.result != 'success'", jobs["format"]["if"])

    def test_required_lint_runs_when_guidance_fails_after_docs_classification(self):
        condition = self.github["jobs"]["format"]["if"]
        for result, docs_only, expected in (
            ("success", "true", False),
            ("failure", "true", True),
            ("failure", "", True),
            ("success", "false", True),
        ):
            with self.subTest(result=result, docs_only=docs_only):
                expression = condition.removeprefix("${{").removesuffix("}}")
                substitutions = {
                    "contains(github.event.pull_request.title, 'NO-CI')": "False",
                    "cancelled()": "False",
                    "github.event_name": repr("pull_request"),
                    "needs.changes.result": repr(result),
                    "needs.changes.outputs.docs_only": repr(docs_only),
                }
                for source, replacement in substitutions.items():
                    expression = expression.replace(source, replacement)
                expression = expression.replace("&&", "and").replace("||", "or")
                expression = re.sub(r"!(?!=)", "not ", expression).strip()
                tree = ast.parse(expression, mode="eval")
                allowed = (
                    ast.Expression,
                    ast.BoolOp,
                    ast.UnaryOp,
                    ast.Compare,
                    ast.Constant,
                    ast.And,
                    ast.Or,
                    ast.Not,
                    ast.Eq,
                    ast.NotEq,
                )
                self.assertTrue(
                    all(isinstance(node, allowed) for node in ast.walk(tree))
                )
                self.assertEqual(
                    eval(
                        compile(tree, "<job condition>", "eval"), {"__builtins__": {}}
                    ),
                    expected,
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
