"""Ownership of suites sharing the ordinary iOS test host."""

import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from grouped_tests import GroupedTestSuites


class GroupedTestSuiteTests(unittest.TestCase):
    def test_artifact_inventory_serves_nested_cases_without_xcode(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest = root / "manifest.json"
            manifest.write_text(
                json.dumps({"groupedSuiteOwners": {"Outer": "CoreTests"}})
            )
            suites = GroupedTestSuites.from_manifest_or_repository(root, manifest)
            self.assertEqual(suites.bundles, {"CoreTests"})
            for path in (
                "Outer/Inner/test()",
                "GroupedLibraryTests/Outer.Inner/test()",
            ):
                self.assertEqual(suites.logical_bundle(path), "CoreTests")
            with self.assertRaisesRegex(ValueError, "Unknown"):
                suites.logical_bundle("Unknown/test()")

    def test_older_or_missing_manifests_use_repository_ownership(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest = root / "manifest.json"
            with patch.object(GroupedTestSuites, "from_repository") as fallback:
                for content in (None, "{}", '{"groupedSuiteOwners": []}'):
                    if content is not None:
                        manifest.write_text(content)
                    if content and "groupedSuiteOwners" in content:
                        with self.assertRaisesRegex(
                            ValueError, "invalid groupedSuiteOwners"
                        ):
                            GroupedTestSuites.from_manifest_or_repository(
                                root, manifest
                            )
                    else:
                        self.assertIs(
                            GroupedTestSuites.from_manifest_or_repository(
                                root, manifest
                            ),
                            fallback.return_value,
                        )
                self.assertEqual(fallback.call_count, 2)

    @unittest.skipUnless(shutil.which("xcrun"), "requires Xcode's SwiftSyntax")
    def test_inventory_uses_test_declarations_across_sources_and_extensions(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            modules = ["FeatureTests", "StorageTests"]
            declarations = []
            for module in modules:
                (root / module / "Tests").mkdir(parents=True)
                declarations.append(
                    f'        unitTests(\n            name: "{module}",\n'
                    f'            sources: ["{module}/Tests/**"],\n        ),\n'
                )
            (root / "Project.swift").write_text(
                'private let groupedLibraryTestNames: Set<String> = ["FeatureTests", "StorageTests"]\n'
                + "".join(declarations)
            )
            (root / "FeatureTests/Tests/Features.swift").write_text(
                """
                import Testing
                @Suite("Display title") struct Outer { struct Nested {} }
                extension Outer.Nested { @Test("Case title") func example() {} }
                private struct StoreSuite {}
                // Other helpers and comments mentioning @Test are not test declarations.
                """
            )
            storage = root / "StorageTests/Tests/Storage.swift"
            storage.write_text(
                "struct StoreSuite { @Testing.Test func saves() {} }\n@Test func fileScope(_ index: Int) {}"
            )
            suites = GroupedTestSuites.from_repository(root)
            self.assertEqual(
                suites.owners,
                {
                    "Outer": "FeatureTests",
                    "StoreSuite": "StorageTests",
                    "fileScope(_:)": "StorageTests",
                },
            )
            storage.write_text("private struct Outer { @Test func ambiguous() {} }")
            with self.assertRaisesRegex(ValueError, "Outer belongs to both"):
                GroupedTestSuites.from_repository(root)


if __name__ == "__main__":
    unittest.main()
