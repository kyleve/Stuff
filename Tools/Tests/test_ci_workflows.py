"""Guard required checks and the boundary before expensive runner allocation."""

import ast
import json
import re
import subprocess
import unittest

from Tools.ci_actions_evidence import REQUIRED_ACTIONS_JOBS
from Tools.ci_native_evidence import NATIVE_CONTEXTS
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

    def test_reuse_evidence_covers_every_required_provider_job(self):
        self.assertEqual(
            REQUIRED_ACTIONS_JOBS, {job["name"] for job in self.github["jobs"].values()}
        )
        native_jobs = self.continued["workflows"]["iOS CI"]["jobs"]
        self.assertEqual(
            NATIVE_CONTEXTS,
            {
                "ci/circleci: " + config["name"]
                for item in native_jobs
                for name, config in item.items()
                if name != "validation-skipped"
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
                self.assertIn(
                    "needs.changes.outputs.skip_validation != 'true'", job["if"]
                )
                self.assertIn(
                    "!contains(github.event.pull_request.title, 'NO-CI')", job["if"]
                )
        classifier = jobs["changes"]
        self.assertEqual(classifier["runs-on"], "ubuntu-latest")
        self.assertEqual(classifier["steps"][0]["with"]["fetch-depth"], 0)
        command = classifier["steps"][1]
        self.assertIn("Tools.ci_changes", command["run"])
        self.assertEqual(
            command["env"]["CI_HEAD_SHA"],
            "${{ github.event.pull_request.head.sha || github.sha }}",
        )
        self.assertEqual(
            command["env"]["CI_BASE_SHA"], "${{ github.event.pull_request.base.sha }}"
        )

    def test_github_uses_push_identity_and_reads_evidence_only_on_main_pushes(self):
        classifier = self.github["jobs"]["changes"]
        command = classifier["steps"][1]
        self.assertEqual(
            classifier["permissions"],
            {
                key: "read"
                for key in (
                    "contents",
                    "actions",
                    "pull-requests",
                    "statuses",
                )
            },
        )
        self.assertEqual(
            command["env"]["GH_TOKEN"],
            "${{ github.event_name == 'push' && github.token || '' }}",
        )
        self.assertEqual(
            command["env"]["CI_PUSH_FORCED"], "${{ toJSON(github.event.forced) }}"
        )
        self.assertIn('--push-forced "$CI_PUSH_FORCED"', command["run"])
        self.assertIn('--branch "$GITHUB_REF_NAME"', command["run"])
        self.assertIn('--repository "$GITHUB_REPOSITORY"', command["run"])

    def test_circleci_continues_once_and_inherits_original_parameters(self):
        self.assertTrue(self.setup["setup"])
        self.assertNotIn("setup", self.continued)
        self.assertEqual(len(self.setup["workflows"]), 1)
        parameters = dict(self.continued["parameters"])
        self.assertEqual(
            parameters.pop("skip_validation"), {"type": "boolean", "default": False}
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

        self.assertEqual(
            job["environment"]["CI_CHECKOUT_SHA"], "<< pipeline.git.revision >>"
        )
        self.assertEqual(job["environment"]["CI_BRANCH"], "<< pipeline.git.branch >>")
        self.assertEqual(
            job["environment"]["CI_REPOSITORY"],
            "<< pipeline.event.github.repository.owner.login >>/<< pipeline.event.github.repository.name >>",
        )

    def test_guidance_checks_the_pr_checkout_tree_and_runs_again_in_required_lint(self):
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
        classify_step = next(
            step for step in classifier["steps"] if step.get("id") == "classify"
        )
        self.assertIn("git rev-parse 'HEAD^{tree}'", classify_step["run"])
        proof_name = (
            "${{ github.event_name == 'pull_request' && "
            "format('Check agent guidance for PR #{0} on tree {1}', github.event.number, steps.classify.outputs.tree) "
            "|| 'Agent guidance check' }}"
        )
        for job, name in (
            (classifier, proof_name),
            (jobs["format"], "Agent guidance check"),
        ):
            check = next(step for step in job["steps"] if step.get("name") == name)
            self.assertEqual(check["run"], "mise exec ruby -- ./sync-agents --check")
            self.assertNotIn("if", check)
            self.assertNotIn("continue-on-error", check)
            self.assertNotIn("continue-on-error", job)
        self.assertNotIn("skip_validation", classifier["if"])
        self.assertIn("needs.changes.result != 'success'", jobs["format"]["if"])

    def test_required_lint_runs_when_guidance_fails_after_skip_decision(self):
        condition = self.github["jobs"]["format"]["if"]
        for result, skip_validation, expected in (
            ("success", "true", False),
            ("failure", "true", True),
            ("failure", "", True),
            ("success", "false", True),
        ):
            with self.subTest(result=result, skip_validation=skip_validation):
                expression = condition.removeprefix("${{").removesuffix("}}")
                substitutions = {
                    "contains(github.event.pull_request.title, 'NO-CI')": "False",
                    "cancelled()": "False",
                    "github.event_name": repr("pull_request"),
                    "needs.changes.result": repr(result),
                    "needs.changes.outputs.skip_validation": repr(skip_validation),
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

    def test_circleci_skip_completes_without_any_macos_job(self):
        workflow = self.continued["workflows"]["iOS CI"]
        self.assertIn(
            'pipeline.parameters.manual_full_gate == "true"', workflow["when"]
        )
        self.assertIn('pipeline.git.branch == "main"', workflow["when"])
        self.assertIn("NO-CI", workflow["when"])
        for item in workflow["jobs"]:
            name, options = next(iter(item.items()))
            with self.subTest(job=name):
                if name == "validation-skipped":
                    self.assertEqual(
                        options["filters"], "pipeline.parameters.skip_validation"
                    )
                else:
                    self.assertEqual(
                        options["filters"], "not pipeline.parameters.skip_validation"
                    )
        job = self.continued["jobs"]["validation-skipped"]
        self.assertIn("docker", self.continued["executors"][job["executor"]])
        self.assertEqual(len(job["steps"]), 1)
        self.assertIn("echo", job["steps"][0]["run"])

    def test_publication_workflows_remain_separate_from_validation_selection(self):
        for name in ("Flyover Export", "Installer Archive"):
            workflow = self.continued["workflows"][name]
            self.assertNotIn("skip_validation", json.dumps(workflow))
            self.assertIn('pipeline.event.name == "api"', workflow["when"])
            self.assertIn('pipeline.config.ref == "refs/heads/main"', workflow["when"])
        archive = self.continued["workflows"]["Installer Archive"]["jobs"][0]
        self.assertEqual(
            archive["archive-app"]["context"], "where-distribution-signing"
        )
