#!/usr/bin/env python3
"""Tests for CircleCI compiler-index selection validation and audit."""

import importlib.util
import json
import pathlib
import tempfile
import unittest
import xml.etree.ElementTree as ET


SCRIPT = pathlib.Path(__file__).with_name("test_impact.py")
SPEC = importlib.util.spec_from_file_location("test_impact", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class TestImpactTests(unittest.TestCase):
    def selection(self, directory, scope="suites", identifiers=None):
        path = pathlib.Path(directory) / "selection.json"
        path.write_text(json.dumps({
            "formatVersion": 1,
            "head": "abc123",
            "fallback": False,
            "schemes": {
                "Stuff-iOS-Tests": {
                    "scope": scope,
                    "identifiers": identifiers or [],
                }
            },
        }))
        return path

    def test_validation_accepts_a_suite_selection(self):
        with tempfile.TemporaryDirectory() as directory:
            path = self.selection(directory, identifiers=["WhereCoreTests/CalendarTests"])

            _, scheme = MODULE.load_and_validate(path, "Stuff-iOS-Tests", head="abc123")

            self.assertEqual(scheme["scope"], "suites")

    def test_validation_rejects_the_wrong_commit(self):
        with tempfile.TemporaryDirectory() as directory:
            path = self.selection(directory, identifiers=["WhereCoreTests/CalendarTests"])

            with self.assertRaisesRegex(ValueError, "selection head"):
                MODULE.load_and_validate(path, "Stuff-iOS-Tests", head="different")

    def test_audit_reports_missing_and_unexpected_suites_without_failing(self):
        with tempfile.TemporaryDirectory() as directory:
            path = self.selection(directory, identifiers=["WhereCoreTests/CalendarTests"])
            selection, scheme = MODULE.load_and_validate(
                path, "Stuff-iOS-Tests", head="abc123"
            )
            junit = pathlib.Path(directory) / "results.xml"
            suites = ET.Element("testsuites")
            suite = ET.SubElement(suites, "testsuite")
            ET.SubElement(
                suite,
                "testcase",
                file="OtherTests/OtherSuite",
                name="example",
            )
            ET.ElementTree(suites).write(junit)

            report = MODULE.audit(selection, scheme, junit)

            self.assertEqual(report["executedTestCount"], 1)
            self.assertEqual(
                report["missingSelectedIdentifiers"], ["WhereCoreTests/CalendarTests"]
            )
            self.assertEqual(report["unexpectedExecutedSuites"], ["OtherTests/OtherSuite"])

    def test_audit_limits_a_full_selection_to_the_worker_assignment(self):
        with tempfile.TemporaryDirectory() as directory:
            path = self.selection(
                directory,
                scope="all",
                identifiers=["SnapshotTests/FirstTests", "SnapshotTests/SecondTests"],
            )
            selection, scheme = MODULE.load_and_validate(
                path, "Stuff-iOS-Tests", head="abc123"
            )
            junit = pathlib.Path(directory) / "results.xml"
            suites = ET.Element("testsuites")
            suite = ET.SubElement(suites, "testsuite")
            ET.SubElement(
                suite,
                "testcase",
                file="SnapshotTests/SecondTests",
                name="example",
            )
            ET.ElementTree(suites).write(junit)

            report = MODULE.audit(
                selection,
                scheme,
                junit,
                assigned=["SnapshotTests/SecondTests"],
            )

            self.assertEqual(report["expectedIdentifierCount"], 1)
            self.assertEqual(report["missingSelectedIdentifiers"], [])
            self.assertEqual(report["unexpectedExecutedSuites"], [])

    def test_materialize_intersects_a_suite_selection_with_the_worker_assignment(self):
        scheme = {
            "scope": "suites",
            "identifiers": ["SnapshotTests/SecondTests"],
        }

        identifiers = MODULE.materialize(
            scheme,
            assigned=["SnapshotTests/FirstTests", "SnapshotTests/SecondTests"],
        )

        self.assertEqual(identifiers, ["SnapshotTests/SecondTests"])

    def test_materialize_keeps_a_full_worker_assignment(self):
        scheme = {
            "scope": "all",
            "identifiers": ["SnapshotTests/FirstTests", "SnapshotTests/SecondTests"],
        }

        identifiers = MODULE.materialize(
            scheme,
            assigned=["SnapshotTests/SecondTests"],
        )

        self.assertEqual(identifiers, ["SnapshotTests/SecondTests"])

    def test_materialize_allows_an_empty_shard_intersection(self):
        scheme = {
            "scope": "suites",
            "identifiers": ["SnapshotTests/FirstTests"],
        }

        identifiers = MODULE.materialize(
            scheme,
            assigned=["SnapshotTests/SecondTests"],
        )

        self.assertEqual(identifiers, [])


if __name__ == "__main__":
    unittest.main()
