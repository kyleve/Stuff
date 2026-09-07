import importlib.util
import io
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


MODULE_PATH = Path(__file__).resolve().parents[1] / "tla_check.py"
SPEC = importlib.util.spec_from_file_location("tla_check", MODULE_PATH)
tla_check = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
sys.modules[SPEC.name] = tla_check
SPEC.loader.exec_module(tla_check)


class TlaCheckTests(unittest.TestCase):
    def fixture(
        self,
        root: Path,
        cases: list[dict],
        source: str = "pluscal",
    ) -> tuple[Path, Path, Path, Path, object]:
        spec_directory = root / "Example"
        spec_directory.mkdir()
        (spec_directory / "Example.tla").write_text("---- MODULE Example ----\n")
        for case in cases:
            (spec_directory / case["config"]).write_text("SPECIFICATION Spec\n")
        manifest_path = spec_directory / "manifest.json"
        manifest_path.write_text(
            json.dumps({"source": source, "module": "Example.tla", "cases": cases})
        )
        versions = tla_check.ToolVersions("1.7.4", "1.11", "java-version", "sha256")
        return (
            manifest_path,
            spec_directory,
            root / "run",
            root / "tla2tools.jar",
            versions,
        )

    def test_translates_an_isolated_copy_and_records_case_summaries(self):
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
                if "pcal.trans" in command:
                    generated_module = Path(options["cwd"]) / "Example.tla"
                    generated_module.write_text(
                        generated_module.read_text() + "\\* translated\n"
                    )
                    return subprocess.CompletedProcess(command, 0, "", "")
                if "Broken.cfg" in command:
                    return subprocess.CompletedProcess(
                        command,
                        12,
                        "1,234 states generated, 987 distinct states found, "
                        "0 states left on queue.\nInvariant violated\n",
                        "",
                    )
                return subprocess.CompletedProcess(
                    command,
                    0,
                    f"{tla_check.CLEAN_CHECK_MESSAGE}\n"
                    "25 states generated, 20 distinct states found, "
                    "0 states left on queue.\n"
                    "The depth of the complete state graph search is 7.\n",
                    "",
                )

            ticks = iter((1.0, 2.25, 3.0, 3.5))
            output = io.StringIO()
            tla_check.run_manifest(
                *paths,
                environment={"TLA_JAVA": "/opt/exact java/bin/java"},
                process_runner=run,
                output=output,
                monotonic=lambda: next(ticks),
            )

            self.assertEqual(len(commands), 3)
            self.assertEqual(commands[0][0][0], "/opt/exact java/bin/java")
            self.assertIn("pcal.trans", commands[0][0])
            self.assertEqual(commands[0][1], {"cwd": paths[2] / "generated"})
            self.assertEqual(
                commands[1][1],
                {
                    "capture_output": True,
                    "text": True,
                    "cwd": paths[2] / "generated",
                },
            )
            self.assertIn("-metadir", commands[1][0])
            self.assertIn("Current.cfg", commands[1][0])
            self.assertEqual((paths[1] / "Example.tla").read_text(), "---- MODULE Example ----\n")
            self.assertTrue(
                (paths[2] / "generated" / "Example.tla")
                .read_text()
                .endswith("\\* translated\n")
            )
            self.assertTrue(
                (paths[2] / "logs" / "current.log").read_text().startswith("Model")
            )
            self.assertEqual(
                (paths[2] / "logs" / "broken.log").read_text().splitlines()[-1],
                "Invariant violated",
            )
            self.assertIn("translating Example.tla", output.getvalue())
            self.assertIn("ok   current (pass; 25 generated", output.getvalue())
            self.assertIn("ok   broken (expected failure; 1234 generated", output.getvalue())
            self.assertIn(f"artifacts: {paths[2]}", output.getvalue())

            summary = json.loads((paths[2] / "summary.json").read_text())
            self.assertEqual(summary["source"], "pluscal")
            self.assertEqual(summary["translation"]["status"], "generated")
            self.assertEqual(summary["translation"]["module"], "generated/Example.tla")
            self.assertEqual(summary["cases"][0]["stats"]["depth"], 7)
            self.assertEqual(summary["cases"][0]["stats"]["elapsedSeconds"], 1.25)
            self.assertEqual(summary["cases"][1]["stats"]["generatedStates"], 1234)
            self.assertEqual(summary["cases"][1]["matchedFailure"], "Invariant violated")

    def test_tla_source_skips_translation(self):
        cases = [{"name": "current", "config": "Current.cfg", "expect": "pass"}]
        with tempfile.TemporaryDirectory() as temporary:
            paths = self.fixture(Path(temporary), cases, source="tla")
            commands = []

            def run(command, **options):
                commands.append(command)
                return subprocess.CompletedProcess(
                    command, 0, f"{tla_check.CLEAN_CHECK_MESSAGE}\n", ""
                )

            tla_check.run_manifest(*paths, process_runner=run)

            self.assertEqual(len(commands), 1)
            self.assertNotIn("pcal.trans", commands[0])
            summary = json.loads((paths[2] / "summary.json").read_text())
            self.assertEqual(summary["translation"]["status"], "not-required")

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

    def test_validates_every_fixture_before_starting_translation_or_tlc(self):
        cases = [
            {"name": "current", "config": "Current.cfg", "expect": "pass"},
            {"name": "missing", "config": "Missing.cfg", "expect": "pass"},
        ]
        with tempfile.TemporaryDirectory() as temporary:
            paths = self.fixture(Path(temporary), cases)
            (paths[1] / "Missing.cfg").unlink()
            calls = []

            with self.assertRaisesRegex(tla_check.TlaCheckError, "Missing.cfg.*not found"):
                tla_check.run_manifest(
                    *paths, process_runner=lambda *args, **kwargs: calls.append(args)
                )

            self.assertEqual(calls, [])
            self.assertFalse(paths[2].exists())

    def test_rejects_module_and_config_paths_outside_the_spec(self):
        cases = [{"name": "current", "config": "Current.cfg", "expect": "pass"}]
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            paths = self.fixture(root, cases)
            outside_module = root / "Outside.tla"
            outside_module.write_text("---- MODULE Outside ----\n")
            paths[0].write_text(
                json.dumps(
                    {
                        "source": "tla",
                        "module": "../Outside.tla",
                        "cases": cases,
                    }
                )
            )

            with self.assertRaisesRegex(tla_check.TlaCheckError, "module.*escapes"):
                tla_check.run_manifest(*paths)

            outside_config = root / "Outside.cfg"
            outside_config.write_text("SPECIFICATION Spec\n")
            paths[0].write_text(
                json.dumps(
                    {
                        "source": "tla",
                        "module": "Example.tla",
                        "cases": [
                            {
                                "name": "current",
                                "config": str(outside_config),
                                "expect": "pass",
                            }
                        ],
                    }
                )
            )

            with self.assertRaisesRegex(tla_check.TlaCheckError, "config.*escapes"):
                tla_check.run_manifest(*paths)

            self.assertFalse(paths[2].exists())

    def test_requires_the_clean_completion_marker_for_a_passing_case(self):
        cases = [{"name": "current", "config": "Current.cfg", "expect": "pass"}]
        with tempfile.TemporaryDirectory() as temporary:
            paths = self.fixture(Path(temporary), cases, source="tla")
            result = subprocess.CompletedProcess([], 0, "TLC exited quietly", "")
            with self.assertRaisesRegex(tla_check.TlaCheckError, "did not report a clean check"):
                tla_check.run_manifest(
                    *paths, process_runner=lambda *args, **kwargs: result
                )

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
            paths = self.fixture(Path(temporary), cases, source="tla")
            result = subprocess.CompletedProcess([], 1, "Different failure", "")
            with self.assertRaisesRegex(tla_check.TlaCheckError, "Specific invariant"):
                tla_check.run_manifest(
                    *paths, process_runner=lambda *args, **kwargs: result
                )

    def test_translation_failure_is_recorded(self):
        cases = [{"name": "current", "config": "Current.cfg", "expect": "pass"}]
        with tempfile.TemporaryDirectory() as temporary:
            paths = self.fixture(Path(temporary), cases)
            result = subprocess.CompletedProcess([], 1, "", "translator failed")
            with self.assertRaisesRegex(tla_check.TlaCheckError, "FAIL translation"):
                tla_check.run_manifest(
                    *paths, process_runner=lambda *args, **kwargs: result
                )

            summary = json.loads((paths[2] / "summary.json").read_text())
            self.assertEqual(summary["translation"]["status"], "failed")
            self.assertEqual(summary["cases"], [])

    def test_rejects_a_tracked_source_change_during_the_run(self):
        cases = [{"name": "current", "config": "Current.cfg", "expect": "pass"}]
        with tempfile.TemporaryDirectory() as temporary:
            paths = self.fixture(Path(temporary), cases)
            call_count = 0

            def run(command, **options):
                nonlocal call_count
                call_count += 1
                if call_count == 1:
                    (paths[1] / "Example.tla").write_text("changed\n")
                    return subprocess.CompletedProcess(command, 0, "", "")
                return subprocess.CompletedProcess(
                    command, 0, f"{tla_check.CLEAN_CHECK_MESSAGE}\n", ""
                )

            with self.assertRaisesRegex(tla_check.TlaCheckError, "source changed"):
                tla_check.run_manifest(*paths, process_runner=run)

    def test_rejects_duplicate_cases_unknown_expectations_and_sources(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            path = root / "manifest.json"
            path.write_text(
                json.dumps(
                    {
                        "source": "pluscal",
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
                        "source": "pluscal",
                        "module": "Example.tla",
                        "cases": [
                            {"name": "one", "config": "A.cfg", "expect": "maybe"}
                        ],
                    }
                )
            )
            with self.assertRaisesRegex(tla_check.TlaCheckError, "unknown expect 'maybe'"):
                tla_check.load_manifest(path)

            path.write_text(
                json.dumps(
                    {
                        "source": "other",
                        "module": "Example.tla",
                        "cases": [
                            {"name": "one", "config": "A.cfg", "expect": "pass"}
                        ],
                    }
                )
            )
            with self.assertRaisesRegex(tla_check.TlaCheckError, "pluscal.*tla"):
                tla_check.load_manifest(path)

    def test_rejects_truncated_manifest_json(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "manifest.json"
            path.write_text('{"source": "tla",')

            with self.assertRaisesRegex(tla_check.TlaCheckError, "could not read"):
                tla_check.load_manifest(path)

    def test_main_surfaces_missing_mise_and_output_directory_failures(self):
        cases = [{"name": "current", "config": "Current.cfg", "expect": "pass"}]
        with tempfile.TemporaryDirectory() as temporary:
            paths = self.fixture(Path(temporary), cases, source="tla")
            arguments = [*(str(path) for path in paths[:4]), *paths[4].__dict__.values()]
            stderr = io.StringIO()

            with patch.object(
                tla_check.subprocess,
                "run",
                side_effect=FileNotFoundError("mise is not installed"),
            ), patch.object(tla_check.sys, "stderr", stderr):
                self.assertEqual(1, tla_check.main(arguments))

            self.assertIn("mise is not installed", stderr.getvalue())

        with tempfile.TemporaryDirectory() as temporary:
            paths = self.fixture(Path(temporary), cases, source="tla")
            paths[2].write_text("not a directory")
            arguments = [*(str(path) for path in paths[:4]), *paths[4].__dict__.values()]
            stderr = io.StringIO()

            with patch.object(tla_check.sys, "stderr", stderr):
                self.assertEqual(1, tla_check.main(arguments))

            self.assertIn("File exists", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
