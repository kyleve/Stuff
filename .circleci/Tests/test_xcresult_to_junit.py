#!/usr/bin/env python3
"""Tests for the CircleCI JUnit converter."""

import importlib.util
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET


SCRIPT = pathlib.Path(__file__).parents[1] / "xcresult_to_junit.py"
SPEC = importlib.util.spec_from_file_location("xcresult_to_junit", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class JUnitTests(unittest.TestCase):
    def test_cli_rejects_malformed_results_but_accepts_an_empty_tree(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            (root / "input" / "result.xcresult").mkdir(parents=True)
            command = root / "xcrun"
            command.write_text(
                f"#!{sys.executable}\nimport os\nprint(os.environ['XCODE_TEST_JSON'])\n"
            )
            command.chmod(0o755)
            output = root / "results.xml"
            for document in (
                [],
                {"testNodes": [42]},
                {"testNodes": [{"children": [42]}]},
            ):
                with self.subTest(document=document):
                    completed = subprocess.run(
                        [sys.executable, str(SCRIPT), str(root / "input"), str(output)],
                        env={
                            **os.environ,
                            "PATH": str(root) + os.pathsep + os.environ["PATH"],
                            "XCODE_TEST_JSON": json.dumps(document),
                        },
                        capture_output=True,
                        text=True,
                        check=False,
                    )
                    self.assertNotEqual(completed.returncode, 0)
                    self.assertFalse(output.exists())
                    self.assertIn("AttributeError", completed.stderr)
            completed = subprocess.run(
                [sys.executable, str(SCRIPT), str(root / "input"), str(output)],
                env={
                    **os.environ,
                    "PATH": str(root) + os.pathsep + os.environ["PATH"],
                    "XCODE_TEST_JSON": '{"testNodes": []}',
                },
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertEqual(ET.parse(output).findall("./testsuite/testcase"), [])

    def test_converter_preserves_precision_and_sums_parameterized_executions(self):
        document = {
            "testNodes": [
                {
                    "nodeType": "Unit test bundle",
                    "name": "CoreTests",
                    "children": [
                        {
                            "nodeType": "Test Suite",
                            "name": "ValuesTests",
                            "children": [
                                {
                                    "nodeType": "Test Case",
                                    "name": "values(_:)",
                                    "result": "Passed",
                                    "duration": "8s",
                                    "durationInSeconds": 8.503,
                                    "children": [
                                        {
                                            "nodeType": "Arguments",
                                            "duration": "0.22s",
                                            "durationInSeconds": 0.221,
                                        },
                                        {
                                            "nodeType": "Arguments",
                                            "duration": "16s",
                                            "durationInSeconds": 16.785,
                                        },
                                    ],
                                }
                            ],
                        }
                    ],
                }
            ]
        }
        with patch.object(MODULE.subprocess, "run") as run:
            run.return_value.returncode = 0
            run.return_value.stdout = json.dumps(document)
            cases = MODULE.test_cases_in(pathlib.Path("result.xcresult"))

        with tempfile.TemporaryDirectory() as directory:
            output = pathlib.Path(directory) / "results.xml"
            MODULE.write_junit(cases, output)
            records = ET.parse(output).findall("./testsuite/testcase")
            self.assertEqual(len(records), 1)
            self.assertEqual(records[0].get("time"), "17.006")
            self.assertEqual(records[0].get("file"), "CoreTests/ValuesTests")

    def test_duration_reads_xcode_compound_units(self):
        self.assertEqual(MODULE.duration({"duration": "1m 12s"}), 72.0)
        self.assertEqual(MODULE.duration({"duration": "1h 2m 3.5s"}), 3723.5)
        self.assertEqual(MODULE.duration({"duration": "320ms"}), 0.32)

    def test_duration_rejects_unknown_formats(self):
        self.assertEqual(MODULE.duration({"duration": "not a duration"}), 0.0)

    def test_case_uses_bundle_and_suite_as_timing_file(self):
        with tempfile.TemporaryDirectory() as directory:
            output = pathlib.Path(directory) / "results.xml"
            MODULE.write_junit(
                [("WhereUISnapshotTests", "CalendarTests", "calendar", "Passed", 1.25)],
                output,
            )

            test_case = ET.parse(output).find("./testsuite/testcase")
            self.assertEqual(
                test_case.get("file"), "WhereUISnapshotTests/CalendarTests"
            )
            self.assertEqual(test_case.get("time"), "1.250")


if __name__ == "__main__":
    unittest.main()
