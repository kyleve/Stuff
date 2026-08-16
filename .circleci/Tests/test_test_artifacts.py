#!/usr/bin/env python3
"""Tests for the iOS test-build manifest and suite parser."""

import importlib.util
import json
import pathlib
import tempfile
import unittest
from unittest import mock


SCRIPT = pathlib.Path(__file__).parents[1] / "test_artifacts.py"
SPEC = importlib.util.spec_from_file_location("test_artifacts", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

METADATA = {
    "checkout": "/Users/distiller/project",
    "commit": "abc123",
    "xcodeBuild": "27A5228h",
    "sdkBuild": "24A123",
    "architecture": "arm64",
    "configuration": "Debug",
}


class ArtifactTests(unittest.TestCase):
    def make_artifacts(self, directory):
        root = pathlib.Path(directory).resolve()
        products = root / "DerivedData" / "Build" / "Products"
        (products / "Debug-iphonesimulator").mkdir(parents=True)
        (products / "StuffSnapshotTests_iphonesimulator27.0-arm64.xctestrun").touch()
        return root

    def test_manifest_resolves_the_test_run_file(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self.make_artifacts(directory)
            MODULE.create_manifest(root, ["StuffSnapshotTests"], METADATA)

            path = MODULE.resolved_path(
                root, "StuffSnapshotTests", "xctestrun", METADATA
            )

            self.assertEqual(path.suffix, ".xctestrun")

    def test_manifest_resolves_all_paths_after_one_validation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self.make_artifacts(directory)
            MODULE.create_manifest(root, ["StuffSnapshotTests"], METADATA)

            with mock.patch.object(
                MODULE,
                "load_and_validate",
                wraps=MODULE.load_and_validate,
            ) as validate:
                paths = MODULE.resolved_paths(
                    root, ["StuffSnapshotTests"], METADATA
                )

            self.assertEqual(
                paths["products"],
                str(
                    root
                    / "DerivedData"
                    / "Build"
                    / "Products"
                    / "Debug-iphonesimulator"
                ),
            )
            self.assertEqual(
                pathlib.Path(paths["schemes"]["StuffSnapshotTests"]).suffix,
                ".xctestrun",
            )
            validate.assert_called_once_with(root, METADATA)

    def test_manifest_rejects_a_different_commit(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self.make_artifacts(directory)
            MODULE.create_manifest(root, ["StuffSnapshotTests"], METADATA)
            different = {**METADATA, "commit": "def456"}

            with self.assertRaisesRegex(ValueError, "test artifact commit"):
                MODULE.load_and_validate(root, different)

    def test_manifest_rejects_more_than_one_test_run_for_a_scheme(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self.make_artifacts(directory)
            products = root / "DerivedData" / "Build" / "Products"
            (products / "StuffSnapshotTests_second.xctestrun").touch()

            with self.assertRaisesRegex(ValueError, "expected one .xctestrun"):
                MODULE.create_manifest(root, ["StuffSnapshotTests"], METADATA)

    def test_manifest_rejects_a_path_outside_the_artifact_root(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self.make_artifacts(directory)
            manifest = MODULE.create_manifest(root, ["StuffSnapshotTests"], METADATA)
            manifest["builtProducts"] = "../Products"
            (root / "manifest.json").write_text(json.dumps(manifest))

            with self.assertRaisesRegex(ValueError, "leaves the artifact root"):
                MODULE.load_and_validate(root, METADATA)

    def test_suite_parser_collapses_tests_to_bundle_and_suite(self):
        enumeration = {
            "values": [
                {
                    "kind": "target",
                    "name": "WhereUISnapshotTests",
                    "children": [
                        {
                            "kind": "class",
                            "name": "CalendarSnapshotTests",
                            "children": [
                                {"kind": "test", "name": "calendarContent()"},
                                {"kind": "test", "name": "calendarDark()"},
                            ],
                        }
                    ],
                }
            ]
        }

        self.assertEqual(
            MODULE.suite_identifiers(enumeration),
            ["WhereUISnapshotTests/CalendarSnapshotTests"],
        )

    def test_suite_parser_rejects_empty_input_in_the_cli_contract(self):
        self.assertEqual(MODULE.suite_identifiers(json.loads("{}")), [])


if __name__ == "__main__":
    unittest.main()
