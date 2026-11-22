"""Guard required checks and the boundary before expensive runner allocation."""

import ast
import json
import re
from pathlib import Path
import tempfile
import subprocess
import unittest

from Tools.repository import repository_root


class CIWorkflowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = repository_root(__file__)
        cls.validation_jobs = json.loads(
            (root / "Tools/ci-validation-jobs.json").read_text()
        )
        cls.github, cls.setup, cls.continued, cls.distribution = json.loads(
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
                    str(root / ".github/workflows/installer-distribute-app.yml"),
                ],
                text=True,
            )
        )
        cls.native_workflow = cls.continued["workflows"][
            cls.validation_jobs["circleci"]["workflow"]
        ]

    def test_github_keeps_workflow_triggers(self):
        triggers = self.github.get("on", self.github.get("true"))
        self.assertEqual(set(triggers), {"push", "pull_request", "workflow_dispatch"})
        self.assertEqual(triggers["pull_request"], {"branches": ["main"]})
        self.assertEqual(triggers["push"], {"branches": ["main"]})

    def test_manifest_matches_github_classifier_and_all_workers(self):
        jobs = self.github["jobs"]
        expected = self.validation_jobs["github_actions"]
        self.assertEqual(jobs["changes"]["name"], expected["classifier"])
        self.assertEqual(len({job["name"] for job in jobs.values()}), len(jobs))
        self.assertEqual(
            sorted(job["name"] for key, job in jobs.items() if key != "changes"),
            sorted(expected["workers"]),
        )

    def test_manifest_matches_all_native_validation_jobs(self):
        jobs = [
            (key, options["name"])
            for item in self.native_workflow["jobs"]
            for key, options in item.items()
        ]
        self.assertEqual(len({name for _, name in jobs}), len(jobs))
        skipped_names = [name for key, name in jobs if key == "validation-skipped"]
        self.assertEqual(
            skipped_names, [self.validation_jobs["circleci"]["skipped_job"]]
        )
        full_names = [name for key, name in jobs if key != "validation-skipped"]
        self.assertEqual(
            sorted(full_names), sorted(self.validation_jobs["circleci"]["jobs"])
        )

    def test_snapshot_inventory_runs_once_after_exporting_unit_results(self):
        jobs = self.continued["jobs"]
        owners = [
            (job, index)
            for job, config in jobs.items()
            for index, step in enumerate(config["steps"])
            if isinstance(step, dict)
            and isinstance(step.get("run"), dict)
            and step["run"].get("command")
            == "bash .circleci/validate_snapshot_inventory.sh"
        ]
        self.assertEqual([job for job, _ in owners], ["test-ios"])
        steps = jobs["test-ios"]["steps"]
        _, gate = owners[0]
        self.assertTrue(any("export_test_results" in step for step in steps[:gate]))
        self.assertTrue(
            any("collect_diagnostics" in step for step in steps[gate + 1 :])
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
            command["env"]["CI_BASE_SHA"],
            "${{ github.event_name == 'push' && github.event.before || github.event.pull_request.base.sha }}",
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
        workflow = self.native_workflow
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

    def test_where_release_builds_run_only_in_the_daily_main_workflow(self):
        daily = self.validation_jobs["daily_where_audiences"]
        workflows = self.continued["workflows"]
        audience_jobs = [
            (name, item["build-where-audiences"])
            for name, workflow in workflows.items()
            for item in workflow["jobs"]
            if "build-where-audiences" in item
        ]
        self.assertEqual(audience_jobs, [(daily["workflow"], {"name": daily["job"]})])
        conditions = {
            'pipeline.event.name == "schedule"',
            'pipeline.git.branch == "main"',
            'pipeline.config.ref == "refs/heads/main"',
        }
        workflow_condition = workflows[daily["workflow"]]["when"]
        self.assertEqual(set(workflow_condition.split(" and ")), conditions)
        self.assertIn(
            f"({workflow_condition})",
            self.setup["workflows"]["Select workflows"]["when"],
        )
        audience = self.continued["jobs"]["build-where-audiences"]
        self.assertIn("macos", self.continued["executors"][audience["executor"]])
        self.assertEqual(audience["parallelism"], 2)
        commands = "\n".join(
            step["run"]["command"] for step in audience["steps"] if "run" in step
        )
        self.assertIn('0) scheme="Where Beta"', commands)
        self.assertIn('1) scheme="Where App Store"', commands)

    def test_schedule_halts_before_continuation_only_after_verified_success(self):
        steps = self.setup["jobs"]["select-workflows"]["steps"]
        gate = next(step["when"] for step in steps[:-1] if "when" in step)
        self.assertEqual(
            gate["condition"],
            {
                "and": [
                    {"equal": ["schedule", "<< pipeline.event.name >>"]},
                    {"equal": ["false", "<< pipeline.parameters.manual_full_gate >>"]},
                ]
            },
        )
        command = gate["steps"][0]["run"]["command"]
        shell = """
            proof_status="$1"
            python3() { [[ "$*" == "-m Tools.ci_daily_audiences" ]] || exit 99; return "$proof_status"; }
            circleci-agent() { [[ "$*" == "step halt" ]] || exit 99; echo halted; }
        """
        for proof_status, expected in ((0, "halted"), (1, ""), (2, "")):
            with self.subTest(proof_status=proof_status):
                result = subprocess.check_output(
                    [
                        "bash",
                        "-eu",
                        "-c",
                        shell + command,
                        "selector",
                        str(proof_status),
                    ],
                    text=True,
                )
                self.assertEqual(result.strip(), expected)

    def test_superseded_main_halts_only_after_uploading_its_marker(self):
        steps = self.continued["jobs"]["archive-app"]["steps"]
        upload = next(
            i
            for i, step in enumerate(steps)
            if isinstance(step, dict) and "store_artifacts" in step
        )
        marker_dir = steps[upload]["store_artifacts"]
        self.assertEqual(
            marker_dir,
            {"path": "/tmp/installer-archive/eligibility", "destination": "installer"},
        )
        prepare = steps[upload - 1]["run"]["command"]
        self.assertIn('mkdir -p "$RUNNER_TEMP/eligibility"', prepare)
        self.assertIn(
            '--superseded-marker "$RUNNER_TEMP/eligibility/superseded-main"', prepare
        )
        halt = steps[upload + 1]["run"]["command"]
        self.assertTrue(
            any(
                "Install temporary signing material" in str(step)
                for step in steps[upload + 2 :]
            )
        )
        for stale in (False, True):
            with self.subTest(stale=stale), tempfile.TemporaryDirectory() as temporary:
                directory = Path(temporary) / "eligibility"
                directory.mkdir()
                if stale:
                    (directory / "superseded-main").write_text("superseded commit")
                output = subprocess.check_output(
                    [
                        "bash",
                        "-eu",
                        "-c",
                        'RUNNER_TEMP=$1; circleci-agent() { [[ "$*" == "step halt" ]] && echo halted; }; '
                        + halt,
                        "test",
                        temporary,
                    ],
                    text=True,
                )
                self.assertEqual(output.strip(), "halted" if stale else "")

    def test_archive_handoff_routes_ready_skipped_and_failed_jobs(self):
        jobs = self.distribution["jobs"]
        archive = jobs["archive"]
        steps = archive["steps"]
        self.assertEqual(
            archive["outputs"]["outcome"], "${{ steps.archive.outputs.outcome }}"
        )
        controller = next(step for step in steps if step.get("id") == "archive")
        self.assertIn('--github-output "$GITHUB_OUTPUT"', controller["run"])
        cleanup = next(
            step for step in steps if "--clear-superseded" in step.get("run", "")
        )
        upload = next(
            step for step in steps if "upload-artifact" in step.get("uses", "")
        )
        self.assertEqual(cleanup["if"], "steps.archive.outputs.outcome == 'superseded'")
        self.assertEqual(upload["if"], "steps.archive.outputs.outcome == 'archived'")
        self.assertEqual(upload["with"]["if-no-files-found"], "error")
        # Ruby and these Actions gates share the same boolean and comparison operators.
        script = f"""
            def always; true; end
            needs = JSON.parse(ARGV.fetch(0), object_class: OpenStruct)
            puts JSON.generate([{jobs["publish"]["if"]}, {jobs["publication-failed"]["if"]}])
        """
        for action, result, outcome, publish, expected in (
            ("publish", "success", "archived", "success", [True, False]),
            ("publish", "success", "archived", "failure", [True, True]),
            ("publish", "success", "superseded", "skipped", [False, False]),
            ("publish", "failure", "superseded", "skipped", [False, True]),
            ("publish", "failure", "", "skipped", [False, True]),
            ("publish", "success", "", "skipped", [False, True]),
            ("retire", "skipped", "", "success", [True, False]),
        ):
            with self.subTest(
                action=action, result=result, outcome=outcome, publish=publish
            ):
                needs = {
                    "plan": {"result": "success", "outputs": {"action": action}},
                    "archive": {"result": result, "outputs": {"outcome": outcome}},
                    "publish": {"result": publish},
                }
                actual = subprocess.check_output(
                    ["ruby", "-rjson", "-rostruct", "-e", script, json.dumps(needs)],
                    text=True,
                )
                self.assertEqual(json.loads(actual), expected)

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
