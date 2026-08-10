import importlib.util
import io
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).resolve().parents[1] / "tla_check.py"
SPEC = importlib.util.spec_from_file_location("tla_check", MODULE_PATH)
tla_check = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
sys.modules[SPEC.name] = tla_check
SPEC.loader.exec_module(tla_check)


class TlaCheckTests(unittest.TestCase):
    def fixture(self, root: Path, cases: list[dict]) -> tuple[Path, Path, Path, Path, Path]:
        spec_directory = root / "Example"
        spec_directory.mkdir()
        (spec_directory / "Example.tla").write_text("---- MODULE Example ----\n")
        for case in cases:
            (spec_directory / case["config"]).write_text("SPECIFICATION Spec\n")
        manifest_path = spec_directory / "manifest.json"
        manifest_path.write_text(json.dumps({"module": "Example.tla", "cases": cases}))
        return (
            manifest_path,
            spec_directory,
            root / "run" / "logs",
            root / "run" / "states",
            root / "tla2tools.jar",
        )

    def test_runs_pass_and_expected_failure_cases_with_exact_java_override(self):
        cases = [
            {"name": "current", "config": "Current.cfg", "expect": "pass"},
            {
                "name": "broken",
                "config": "Broken.cfg",
                "expect": "fail",
                "outputContains": "Invariant violated",
            },
        ]
        with tempfile.TemporaryDirectory() as temporary:
            paths = self.fixture(Path(temporary), cases)
            commands = []

            def run(command, **options):
                commands.append((command, options))
                if any(argument.endswith("/Broken.cfg") for argument in command):
                    return subprocess.CompletedProcess(command, 12, "", "Invariant violated\n")
                return subprocess.CompletedProcess(
                    command, 0, f"{tla_check.CLEAN_CHECK_MESSAGE}\n", ""
                )

            output = io.StringIO()
            tla_check.run_manifest(
                *paths,
                environment={"TLA_JAVA": "/opt/exact java/bin/java"},
                process_runner=run,
                output=output,
            )

            self.assertEqual(len(commands), 2)
            self.assertEqual(commands[0][0][0], "/opt/exact java/bin/java")
            self.assertEqual(commands[0][1], {"capture_output": True, "text": True})
            self.assertIn("-metadir", commands[0][0])
            self.assertTrue((paths[2] / "current.log").read_text().startswith("Model"))
            self.assertEqual((paths[2] / "broken.log").read_text(), "Invariant violated\n")
            self.assertIn("ok   current (pass)", output.getvalue())
            self.assertIn("ok   broken (expected failure)", output.getvalue())
            self.assertIn(f"artifacts: {paths[2].parent}", output.getvalue())

    def test_uses_the_pinned_mise_java_when_no_override_is_present(self):
        prefix = tla_check.java_command_prefix({})
        self.assertEqual(
            prefix,
            [
                "mise",
                "--yes",
                "--no-config",
                "x",
                f"java@{tla_check.JAVA_VERSION}",
                "--",
                "java",
            ],
        )

    def test_validates_every_fixture_before_starting_tlc(self):
        cases = [
            {"name": "current", "config": "Current.cfg", "expect": "pass"},
            {"name": "missing", "config": "Missing.cfg", "expect": "pass"},
        ]
        with tempfile.TemporaryDirectory() as temporary:
            paths = self.fixture(Path(temporary), cases)
            (paths[1] / "Missing.cfg").unlink()
            calls = []

            with self.assertRaisesRegex(tla_check.TlaCheckError, "Missing.cfg.*not found"):
                tla_check.run_manifest(*paths, process_runner=lambda *args, **kwargs: calls.append(args))

            self.assertEqual(calls, [])

    def test_requires_the_clean_completion_marker_for_a_passing_case(self):
        cases = [{"name": "current", "config": "Current.cfg", "expect": "pass"}]
        with tempfile.TemporaryDirectory() as temporary:
            paths = self.fixture(Path(temporary), cases)
            result = subprocess.CompletedProcess([], 0, "TLC exited quietly", "")
            with self.assertRaisesRegex(tla_check.TlaCheckError, "did not report a clean check"):
                tla_check.run_manifest(*paths, process_runner=lambda *args, **kwargs: result)

    def test_expected_failure_requires_its_diagnostic(self):
        cases = [
            {
                "name": "broken",
                "config": "Broken.cfg",
                "expect": "fail",
                "outputContains": "Specific invariant",
            }
        ]
        with tempfile.TemporaryDirectory() as temporary:
            paths = self.fixture(Path(temporary), cases)
            result = subprocess.CompletedProcess([], 1, "Different failure", "")
            with self.assertRaisesRegex(tla_check.TlaCheckError, "Specific invariant"):
                tla_check.run_manifest(*paths, process_runner=lambda *args, **kwargs: result)

    def test_rejects_duplicate_cases_and_unknown_expectations(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            path = root / "manifest.json"
            path.write_text(
                json.dumps(
                    {
                        "module": "Example.tla",
                        "cases": [
                            {"name": "same", "config": "A.cfg", "expect": "pass"},
                            {"name": "same", "config": "B.cfg", "expect": "pass"},
                        ],
                    }
                )
            )
            with self.assertRaisesRegex(tla_check.TlaCheckError, "duplicate case name"):
                tla_check.load_manifest(path)

            path.write_text(
                json.dumps(
                    {
                        "module": "Example.tla",
                        "cases": [{"name": "one", "config": "A.cfg", "expect": "maybe"}],
                    }
                )
            )
            with self.assertRaisesRegex(tla_check.TlaCheckError, "unknown expect 'maybe'"):
                tla_check.load_manifest(path)


if __name__ == "__main__":
    unittest.main()
