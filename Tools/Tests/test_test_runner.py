import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from test_runner import (
    ProgressReporter,
    affected_bundles,
    failure_report,
    main,
    snapshot_bundles,
)


class Clock:
    def __init__(self):
        self.now = 0.0

    def __call__(self):
        return self.now


class TestRunnerTests(unittest.TestCase):
    def test_affected_bundles_follows_package_dependents_and_test_ownership(self):
        package = {
            "targets": [
                {"name": "Core", "path": "Shared/Core", "dependencies": []},
                {
                    "name": "UI",
                    "path": "Shared/UI",
                    "dependencies": [{"target": ["Core"]}],
                },
            ]
        }
        project = self.project_with_bundles(
            [("CoreTests", "Shared/Core/Tests", "Core"), ("UITests", "Shared/UI/Tests", "UI")]
        )

        self.assertEqual(
            affected_bundles(["Shared/Core/Sources/Value.swift"], package, project),
            ["CoreTests", "UITests"],
        )
        self.assertEqual(
            affected_bundles(["Shared/Core/Tests/ValueTests.swift"], package, project),
            ["CoreTests"],
        )

    def test_affected_bundles_overselects_global_paths_and_rejects_short_parse(self):
        project = self.project_with_bundles([])
        selected = affected_bundles(["Project.swift"], {"targets": []}, project)
        self.assertEqual(len(selected), 15)

        with self.assertRaisesRegex(ValueError, "only found 0 test bundles"):
            affected_bundles(["Project.swift"], {"targets": []}, "")

    def test_empty_affected_input_does_not_invoke_swift_package_manager(self):
        with patch("sys.stdin", io.StringIO("")), patch(
            "test_runner.subprocess.run"
        ) as run:
            self.assertEqual(main(["affected-bundles"]), 0)
        run.assert_not_called()

    def test_progress_uses_images_without_a_cached_test_total(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output = io.StringIO()
            reporter = ProgressReporter(
                heartbeat=0,
                status_path=None,
                counts_path=root / "counts.json",
                scheme="Snapshots",
                is_terminal=False,
                count_images=True,
                output=output,
                clock=Clock(),
            )

            reporter.consume('SNAPSHOT_TIMING {"id":"one"}')

            self.assertIn("1 images", output.getvalue())

    def test_progress_keeps_cached_test_count_labeled_as_tests(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            counts = root / "counts.json"
            counts.write_text(json.dumps({"tests": 34, "images": 0}))
            output = io.StringIO()
            reporter = ProgressReporter(
                heartbeat=0,
                status_path=None,
                counts_path=counts,
                scheme="Snapshots",
                is_terminal=False,
                count_images=True,
                output=output,
                clock=Clock(),
            )

            reporter.consume('SNAPSHOT_TIMING {"id":"one"}')

            self.assertIn("0/34 tests", output.getvalue())
            self.assertNotIn("images", output.getvalue())

    def test_progress_marks_an_empty_filter_and_clears_it_after_tests_run(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            counts = root / "counts.json"
            output = io.StringIO()
            empty = ProgressReporter(
                heartbeat=15,
                status_path=None,
                counts_path=counts,
                scheme="Unit",
                is_terminal=False,
                count_images=False,
                output=output,
                clock=Clock(),
            )
            empty.finish()
            self.assertTrue(Path(str(counts) + ".empty").exists())
            self.assertIn("this run matched no tests", output.getvalue())

            passing = ProgressReporter(
                heartbeat=0,
                status_path=None,
                counts_path=counts,
                scheme="Unit",
                is_terminal=False,
                count_images=False,
                output=io.StringIO(),
                clock=Clock(),
            )
            passing.consume("◇ Test works() started")
            passing.consume("✔ Test works() passed after 0.001 seconds")
            passing.finish()
            self.assertFalse(Path(str(counts) + ".empty").exists())
            self.assertEqual(json.loads(counts.read_text()), {"tests": 1, "images": 0})

    def test_failure_report_preserves_suite_level_rerun_identifier(self):
        document = {
            "testNodes": [
                {
                    "nodeType": "Unit test bundle",
                    "name": "CoreTests",
                    "children": [
                        {
                            "nodeType": "Test Suite",
                            "name": "ValueTests",
                            "children": [
                                {
                                    "nodeType": "Test Case",
                                    "name": "fails()",
                                    "result": "Failed",
                                }
                            ],
                        }
                    ],
                }
            ]
        }

        report = failure_report(document, "/tmp/tests.xcresult")

        self.assertIn("CoreTests/ValueTests/fails()", report)
        self.assertIn("./test --only 'CoreTests/ValueTests'", report)
        self.assertIn("Result bundle: /tmp/tests.xcresult", report)

    def test_discovers_snapshot_bundles(self):
        project = 'name: "WhereUISnapshotTests"\nname: "WhereUISnapshotTests"\nname: "CoreTests"'
        self.assertEqual(snapshot_bundles(project), ["WhereUISnapshotTests"])

    def project_with_bundles(self, leading):
        bundles = list(leading)
        while len(bundles) < 15:
            index = len(bundles)
            bundles.append((f"Dummy{index}Tests", f"Dummy/{index}/Tests", f"Dummy{index}"))
        windows = []
        for name, sources, product in bundles:
            windows.append(
                "\n".join(
                    [
                        "        unitTests(",
                        f'            name: "{name}",',
                        f'            sources: ["{sources}/**"],',
                        f'            productDependency: "{product}"',
                        "        ),",
                    ]
                )
            )
        return "\n".join(windows)


if __name__ == "__main__":
    unittest.main()
