"""Guard the complete native gate and publication trust boundaries."""

import json
import subprocess
import unittest

from Tools.repository import repository_root


def yaml_files(*names):
    root = repository_root(__file__)
    return json.loads(
        subprocess.check_output(
            [
                "ruby",
                "-ryaml",
                "-rjson",
                "-e",
                "puts JSON.generate(ARGV.map { |path| YAML.load_file(path) })",
                *(str(root / ".circleci" / name) for name in names),
            ],
            text=True,
        )
    )


class CIWorkflowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.setup, cls.jobs, cls.continued, cls.webhook = yaml_files(
            "config.yml", "jobs.yml", "continue.yml", "webhook.yml"
        )

    def test_only_the_pages_upload_bridge_remains(self):
        self.assertEqual(
            [
                p.name
                for p in (repository_root(__file__) / ".github/workflows").glob("*.yml")
            ],
            ["installer-pages.yml"],
        )
        bridge = (
            repository_root(__file__) / ".github/workflows/installer-pages.yml"
        ).read_text()
        self.assertIn("actions/deploy-pages@v4", bridge)
        self.assertIn("pages-publication", bridge)
        self.assertNotIn("npm", bridge)
        self.assertNotIn("CircleCI", bridge.split("jobs:")[1])

    def test_pages_dispatches_coalesce_to_the_latest_generated_commit(self):
        bridge = (
            repository_root(__file__) / ".github/workflows/installer-pages.yml"
        ).read_text()
        self.assertNotIn("client_payload", bridge)
        self.assertIn("git/ref/heads/gh-pages", bridge)
        self.assertIn("ref: ${{ steps.validate.outputs.sha }}", bridge)
        self.assertIn("SITE_COMMIT: ${{ steps.validate.outputs.sha }}", bridge)
        self.assertIn("DEPLOYMENT_STATUS: ${{ job.status }}", bridge)
        self.assertLess(
            bridge.index("actions/deploy-pages"), bridge.index("statuses/$SITE_COMMIT")
        )

    def test_complete_gate_keeps_existing_required_workflow_identity(self):
        workflow = self.continued["workflows"]["iOS CI"]
        self.assertIn(
            'pipeline.parameters.manual_full_gate == "true"', workflow["when"]
        )
        self.assertIn('pipeline.git.branch == "main"', workflow["when"])
        self.assertIn("NO-CI", workflow["when"])
        names = {next(iter(item)) for item in workflow["jobs"]}
        self.assertEqual(
            names,
            {
                "format-and-tools",
                "architecture-and-host",
                "web",
                "documentation-only",
                "build-ios-tests",
                "test-ios",
                "build-where-audiences",
                "snapshot",
            },
        )
        for item in workflow["jobs"]:
            job, options = next(iter(item.items()))
            self.assertEqual(
                options["filters"],
                "pipeline.parameters.docs_only"
                if job == "documentation-only"
                else "not pipeline.parameters.docs_only",
            )
        self.assertEqual(self.jobs["jobs"]["documentation-only"]["executor"], "linux")

    def test_selection_is_unprivileged_and_precedes_all_macos_work(self):
        self.assertTrue(self.setup["setup"])
        job = self.setup["jobs"]["select-workflows"]
        self.assertIn("docker", job)
        self.assertNotIn("context", job)
        self.assertIn("Tools.ci_circleci", job["steps"][-1]["run"]["command"])
        for key, suffix in [("CI_BASE_SHA", "base.sha"), ("CI_HEAD_SHA", "head.sha")]:
            self.assertEqual(
                job["environment"][key],
                f"<< pipeline.event.github.pull_request.{suffix} >>",
            )
        self.assertNotIn("context", json.dumps(self.continued))

    def test_publication_setup_uses_only_trusted_main_config(self):
        for config in (self.setup, self.webhook):
            workflow = config["workflows"]["Select publication"]
            self.assertIn('pipeline.git.branch == "main"', workflow["when"])
            self.assertIn('pipeline.config.ref == "refs/heads/main"', workflow["when"])
            self.assertEqual(
                workflow["jobs"],
                [{"select-publication": {"context": "github-publication"}}],
            )
        env = self.webhook["jobs"]["select-publication"]["environment"]
        self.assertEqual(
            env["PUBLICATION_WEBHOOK"], "<< pipeline.trigger_parameters.webhook.body >>"
        )
        commands = json.dumps(self.webhook["jobs"]["select-publication"]["steps"])
        self.assertNotIn("webhook.body", commands)

    def test_every_former_check_is_in_a_native_job(self):
        text = json.dumps(self.jobs["jobs"])
        for command in (
            "./shellcheck",
            "npm run lint",
            "npm run test:lint",
            "./swiftformat --lint",
            "./sf-symbols --lint",
            "./xcstrings --lint",
            "./attribution --check",
            "unittest discover",
            "Tools/Tests/**/*_test.rb",
            "test_xcresult_to_junit.py",
            "test_test_artifacts.py",
            "./snapshot-shards check",
            "./test --architecture-only",
            "./test --skip-architecture PeriscopeMacrosTests",
            "npm run check",
            "npm run test:unit",
            "npm run test:browser",
        ):
            self.assertIn(command, text)
        self.assertEqual(self.jobs["jobs"]["web"]["executor"], "linux")

    def test_failure_status_and_site_deployment_are_native_dependencies(self):
        finish = self.jobs["jobs"]["finish-app"]
        self.assertEqual(finish["parameters"]["command"]["enum"], ["finish", "fail"])
        self.assertEqual(finish["steps"][-1], "deploy_site")
        self.assertEqual(finish["steps"][-2]["run"]["when"], "on_fail")
        self.assertEqual(
            self.jobs["commands"]["deploy_site"]["steps"][0]["run"]["when"], "always"
        )
        archive = json.dumps(self.jobs["jobs"]["archive-app"])
        self.assertIn("persist_to_workspace", archive)
        self.assertNotIn("GH_TOKEN", archive)
