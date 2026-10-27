import itertools
import json
import os
import subprocess
import unittest

from Tools.repository import repository_root


class CIWorkflowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        path = repository_root(__file__) / ".github/workflows/ci.yml"
        cls.jobs = json.loads(
            subprocess.check_output(
                [
                    "ruby",
                    "-ryaml",
                    "-rjson",
                    "-e",
                    "puts JSON.generate(YAML.load_file(ARGV.fetch(0)))",
                    str(path),
                ],
                text=True,
            )
        )["jobs"]

    def test_required_gate_observes_every_split_job_even_after_failure(self):
        gate = self.jobs["tooling-gate"]
        self.assertEqual(gate["name"], "Lint & Tooling Checks")
        self.assertEqual(set(gate["needs"]), {"format", "test-tools", "test-web"})
        eligibility = self.jobs["format"]["if"]
        for job in ("test-tools", "test-web"):
            self.assertEqual(self.jobs[job]["if"], eligibility)
            self.assertNotIn("needs", self.jobs[job])
        self.assertEqual(gate["if"], "${{ always() && (" + eligibility[4:-3] + ") }}")
        self.assertEqual(len(gate["steps"]), 1)
        step = gate["steps"][0]
        self.assertEqual(
            step["env"],
            {
                "LINT_RESULT": "${{ needs.format.result }}",
                "TOOL_RESULT": "${{ needs.test-tools.result }}",
                "WEB_RESULT": "${{ needs.test-web.result }}",
            },
        )

    def test_required_gate_rejects_each_non_success_result(self):
        step = self.jobs["tooling-gate"]["steps"][0]
        for results in itertools.product(
            ("success", "failure", "cancelled", "skipped"), repeat=3
        ):
            with self.subTest(results=results):
                environment = dict(os.environ)
                environment.update(
                    zip(("LINT_RESULT", "TOOL_RESULT", "WEB_RESULT"), results)
                )
                completed = subprocess.run(
                    ["bash", "-e", "-o", "pipefail", "-c", step["run"]],
                    env=environment,
                    capture_output=True,
                    text=True,
                    check=False,
                )
                self.assertEqual(
                    completed.returncode == 0, all(r == "success" for r in results)
                )


if __name__ == "__main__":
    unittest.main()
