import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).resolve().parents[1] / "snapshot_shards.py"
SPEC = importlib.util.spec_from_file_location("snapshot_shards", MODULE_PATH)
snapshot_shards = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(snapshot_shards)


class SnapshotShardsTests(unittest.TestCase):
    def test_discovers_same_named_suites_from_snapshot_targets(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "Project.swift").write_text(
                '        unitTests(\n'
                '            name: "FeatureSnapshotTests",\n'
                '            sources: ["Feature/SnapshotTests/**"],\n'
                '        ),\n'
            )
            sources = root / "Feature" / "SnapshotTests"
            sources.mkdir(parents=True)
            (sources / "CardSnapshotTests.swift").write_text(
                "struct CardSnapshotTests {}\n"
                "final class SnapshotAlbum {}\n"
            )

            self.assertEqual(
                snapshot_shards.discover_catalog(root),
                ["FeatureSnapshotTests/CardSnapshotTests"],
            )

    def test_discovery_rejects_a_suite_that_does_not_match_its_filename(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "Project.swift").write_text(
                '        unitTests(\n'
                '            name: "FeatureSnapshotTests",\n'
                '            sources: ["Feature/SnapshotTests/**"],\n'
                '        ),\n'
            )
            sources = root / "Feature" / "SnapshotTests"
            sources.mkdir(parents=True)
            (sources / "CardSnapshotTests.swift").write_text("struct OtherTests {}\n")

            with self.assertRaisesRegex(snapshot_shards.ShardError, "exactly one top-level"):
                snapshot_shards.discover_catalog(root)

    def test_discovery_rejects_an_additional_suite_in_the_same_file(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "Project.swift").write_text(
                '        unitTests(\n'
                '            name: "FeatureSnapshotTests",\n'
                '            sources: ["Feature/SnapshotTests/**"],\n'
                '        ),\n'
            )
            sources = root / "Feature" / "SnapshotTests"
            sources.mkdir(parents=True)
            (sources / "CardSnapshotTests.swift").write_text(
                "struct CardSnapshotTests {}\n"
                "struct ExtraSnapshotTests {}\n"
            )

            with self.assertRaisesRegex(
                snapshot_shards.ShardError,
                "found CardSnapshotTests, ExtraSnapshotTests",
            ):
                snapshot_shards.discover_catalog(root)

    def test_validation_reports_missing_duplicate_unknown_and_empty_assignments(self):
        with self.assertRaises(snapshot_shards.ShardError) as raised:
            snapshot_shards.validate_config(
                ["Bundle/One", "Bundle/Two"],
                {"1": ["Bundle/One", "Bundle/One", "Bundle/Unknown"], "2": []},
            )
        message = str(raised.exception)
        self.assertIn("empty shards: 2", message)
        self.assertIn("assigned more than once: Bundle/One", message)
        self.assertIn("missing: Bundle/Two", message)
        self.assertIn("unknown: Bundle/Unknown", message)

    def test_load_config_rejects_an_unsupported_version(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "config.json"
            path.write_text(json.dumps({"version": 2, "shards": {"1": [], "2": []}}))
            with self.assertRaisesRegex(snapshot_shards.ShardError, "unsupported version"):
                snapshot_shards.load_config(path)

    def test_extracts_and_aggregates_test_cases_by_bundle_and_suite(self):
        data = {
            "testNodes": [
                {
                    "nodeType": "Unit test bundle",
                    "name": "FeatureSnapshotTests",
                    "children": [
                        {
                            "nodeType": "Test Suite",
                            "name": "CardSnapshotTests",
                            "children": [
                                {"nodeType": "Test Case", "name": "one()", "durationInSeconds": 2.5, "result": "Passed"},
                                {"nodeType": "Test Case", "name": "two()", "durationInSeconds": 1.5, "result": "Passed"},
                                {"nodeType": "Test Case", "name": "skip()", "durationInSeconds": 10, "result": "Skipped"},
                            ],
                        }
                    ],
                }
            ]
        }

        report = snapshot_shards.make_report([data])

        self.assertEqual(
            report["suites"],
            [{"identifier": "FeatureSnapshotTests/CardSnapshotTests", "durationSeconds": 4.0, "testCount": 2}],
        )

    def test_medians_combine_complete_ci_run_reports(self):
        result = snapshot_shards.medians(
            [
                {"Bundle/One": 10.0, "Bundle/Two": 4.0},
                {"Bundle/One": 20.0, "Bundle/Two": 8.0},
                {"Bundle/One": 12.0, "Bundle/Two": 6.0},
            ]
        )
        self.assertEqual(result, {"Bundle/One": 12.0, "Bundle/Two": 6.0})

    def test_ci_artifact_aggregation_requires_one_copy_of_every_suite(self):
        expected = {"Bundle/One", "Bundle/Two"}
        self.assertEqual(
            snapshot_shards.combine_shard_reports(
                [{"Bundle/One": 1.0}, {"Bundle/Two": 2.0}], expected
            ),
            {"Bundle/One": 1.0, "Bundle/Two": 2.0},
        )
        with self.assertRaisesRegex(snapshot_shards.ShardError, "repeat suites"):
            snapshot_shards.combine_shard_reports(
                [{"Bundle/One": 1.0}, {"Bundle/One": 2.0}], expected
            )
        with self.assertRaisesRegex(snapshot_shards.ShardError, "missing Bundle/Two"):
            snapshot_shards.combine_shard_reports([{"Bundle/One": 1.0}], expected)

    def test_balancing_is_deterministic_and_uses_stable_tie_breaks(self):
        shards, totals = snapshot_shards.balance(
            {"Bundle/D": 4.0, "Bundle/B": 2.0, "Bundle/C": 3.0, "Bundle/A": 4.0}
        )
        self.assertEqual(shards, {"1": ["Bundle/A", "Bundle/C"], "2": ["Bundle/B", "Bundle/D"]})
        self.assertEqual(totals, {"1": 7.0, "2": 6.0})

    def test_load_report_rejects_duplicate_suite_rows(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "report.json"
            row = {"identifier": "Bundle/Suite", "durationSeconds": 1, "testCount": 1}
            path.write_text(json.dumps({"version": 1, "suites": [row, row]}))
            with self.assertRaisesRegex(snapshot_shards.ShardError, "duplicate suite"):
                snapshot_shards.load_report(path)


if __name__ == "__main__":
    unittest.main()
