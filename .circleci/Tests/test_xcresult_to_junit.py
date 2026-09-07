#!/usr/bin/env python3
"""Tests for the CircleCI JUnit converter."""

import importlib.util
import pathlib
import tempfile
import unittest
import xml.etree.ElementTree as ET


SCRIPT = pathlib.Path(__file__).parents[1] / "xcresult_to_junit.py"
SPEC = importlib.util.spec_from_file_location("xcresult_to_junit", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class JUnitTests(unittest.TestCase):
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
            self.assertEqual(test_case.get("file"), "WhereUISnapshotTests/CalendarTests")
            self.assertEqual(test_case.get("time"), "1.250")


if __name__ == "__main__":
    unittest.main()
