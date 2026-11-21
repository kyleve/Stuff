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
    grouped_filters,
    main,
    snapshot_bundles,
)


class Clock:
    def __init__(self):
        self.now = 0.0

    def __call__(self):
        return self.now


class TestRunnerTests(unittest.TestCase):
    def test_grouped_filters_keep_the_owner_of_each_module_and_nested_test(self):
        from grouped_tests import GroupedTestSuites

        suites = GroupedTestSuites(
            bundles={"CoreTests", "UITests"},
            owners={"Writes": "CoreTests", "Reads": "CoreTests", "Views": "UITests"},
        )
        self.assertEqual(
            grouped_filters(
                [
                    "CoreTests",
                    "UITests/Views/Nested/works()",
                    "CoreTests/Writes/Nested",
                    "HostTests/Separate",
                    "CoreTests/Reads",
                ],
                suites,
            ),
            [
                "GroupedLibraryTests/Reads",
                "GroupedLibraryTests/Writes",
                "GroupedLibraryTests/Views/Nested/works()",
                "GroupedLibraryTests/Writes/Nested",
                "HostTests/Separate",
            ],
        )
        with self.assertRaisesRegex(ValueError, "CoreTests has no grouped test suite"):
            grouped_filters(["CoreTests/Views"], suites)

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
            [
                ("CoreTests", "Shared/Core/Tests", "Core"),
                ("UITests", "Shared/UI/Tests", "UI"),
            ]
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

        selected = affected_bundles([".xcode-version"], {"targets": []}, project)
        self.assertEqual(len(selected), 15)

        with self.assertRaisesRegex(ValueError, "only found 0 test bundles"):
            affected_bundles(["Project.swift"], {"targets": []}, "")

    def test_empty_affected_input_does_not_invoke_swift_package_manager(self):
        with (
            patch("sys.stdin", io.StringIO("")),
            patch("test_runner.subprocess.run") as run,
        ):
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

    def test_progress_counts_named_parameterized_and_known_issue_tests_once(self):
        with tempfile.TemporaryDirectory() as directory:
            output = io.StringIO()
            counts = Path(directory) / "counts.json"
            reporter = ProgressReporter(
                heartbeat=0,
                status_path=None,
                counts_path=counts,
                scheme="Unit",
                is_terminal=False,
                count_images=False,
                output=output,
                clock=Clock(),
            )
            reporter.run(
                [
                    '◇ Suite "Readable suite" started.',
                    '◇ Test "Stores the wrapped value" started.',
                    '✔ Test "Stores the wrapped value" passed after 0.001 seconds.',
                    "\u200b✔ Test values(_:) with 200 test cases passed after 0.064 seconds.",
                    "━ Test expectedIssue() passed after 0.075 seconds with 1 known issue.",
                    "\u200b━ Test retry(_:) with 2 test cases passed after 0.069 seconds with 2 known issues.",
                    '✘ Test "Reports a failure" failed after 0.001 seconds.',
                    '\u200b➜ Test manualProbe() skipped: "Opt-in probe."',
                    "✔ Test run with 6 tests in 1 suite passed after 0.2 seconds.",
                ]
            )

            self.assertEqual(reporter.tests, 5)
            self.assertEqual(reporter.failures, 1)
            self.assertIn('"Readable suite"/"Reports a failure"', output.getvalue())
            self.assertIn("5 tests", output.getvalue())
            self.assertEqual(json.loads(counts.read_text()), {"tests": 5, "images": 0})

    def test_retry_diagnostics_are_visible_without_counting_as_tests_or_images(self):
        with tempfile.TemporaryDirectory() as directory:
            output = io.StringIO()
            reporter = ProgressReporter(
                heartbeat=0,
                status_path=None,
                counts_path=Path(directory) / "counts.json",
                scheme="Snapshots",
                is_terminal=False,
                count_images=True,
                output=output,
                clock=Clock(),
            )
            lines = [
                "SNAPSHOT_RETRY example: attempt 1/3 failed: settle timeout; retrying attempt 2/3",
                "SNAPSHOT_RETRY example: recovered on attempt 2/3",
            ]
            for line in lines:
                reporter.consume(line)
                self.assertIn(line, output.getvalue())
            self.assertEqual(reporter.tests, 0)
            self.assertEqual(reporter.images, 0)
            self.assertEqual(reporter.failures, 0)
            reporter.consume('SNAPSHOT_TIMING {"id":"example"}')
            reporter.consume("✔ Test example() passed after 1.0 seconds")
            self.assertEqual(reporter.images, 1)
            self.assertEqual(reporter.tests, 1)
            self.assertEqual(reporter.failures, 0)

    def test_progress_passes_through_flyover_export_status(self):
        with tempfile.TemporaryDirectory() as directory:
            output = io.StringIO()
            reporter = ProgressReporter(
                heartbeat=15,
                status_path=None,
                counts_path=Path(directory) / "counts.json",
                scheme="Snapshots",
                is_terminal=False,
                count_images=False,
                output=output,
                clock=Clock(),
            )

            reporter.consume("FLYOVER_EXPORT 37/110 Locations / Empty / phone-light")

            self.assertIn(
                "FLYOVER_EXPORT 37/110 Locations / Empty / phone-light",
                output.getvalue(),
            )

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

    def test_progress_ignores_schema_shifted_cached_count_fields(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            counts = root / "counts.json"
            counts.write_text(json.dumps({"tests": "34", "images": [9]}))
            output = io.StringIO()
            reporter = ProgressReporter(
                heartbeat=0,
                status_path=None,
                counts_path=counts,
                scheme="Unit",
                is_terminal=False,
                count_images=False,
                output=output,
                clock=Clock(),
            )

            reporter.consume("✔ Test works() passed after 0.001 seconds")

            self.assertIn("1 tests", output.getvalue())
            self.assertNotIn("/34", output.getvalue())

    def test_progress_drops_a_stale_total_after_the_run_exceeds_it(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            counts = root / "counts.json"
            counts.write_text(json.dumps({"tests": 1, "images": 0}))
            output = io.StringIO()
            reporter = ProgressReporter(
                heartbeat=0,
                status_path=root / "missing" / "status.txt",
                counts_path=counts,
                scheme="Unit",
                is_terminal=False,
                count_images=False,
                output=output,
                clock=Clock(),
            )

            for name in ("first()", "second()"):
                reporter.consume(f"◇ Test {name} started")
                reporter.consume(f"✔ Test {name} passed after 0.001 seconds")

            self.assertIn("2 tests", output.getvalue())
            self.assertNotIn("2/1", output.getvalue())

    def test_terminal_progress_redraws_in_place(self):
        with tempfile.TemporaryDirectory() as directory:
            output = io.StringIO()
            reporter = ProgressReporter(
                heartbeat=15,
                status_path=None,
                counts_path=Path(directory) / "counts.json",
                scheme="Unit",
                is_terminal=True,
                count_images=False,
                output=output,
                clock=Clock(),
            )

            reporter.consume("◇ Test works() started")

            self.assertIn("\r\033[K", output.getvalue())
            self.assertIn("works()", output.getvalue())

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

        bundle = document["testNodes"][0]
        bundle["name"] = "GroupedLibraryTests"
        suite = bundle["children"][0]
        suite["name"] = "Displayed title"
        for suite_path in ("ValueTests", "ValueTests/Nested", "ValueTests.Nested"):
            with self.subTest(suite_path=suite_path):
                suite["children"][0]["nodeIdentifier"] = f"{suite_path}/fails()"
                with patch("grouped_tests.GroupedTestSuites.from_repository") as load:
                    load.return_value.owners = {"ValueTests": "CoreTests"}
                    report = failure_report(document, "/tmp/grouped.xcresult")
                self.assertIn("CoreTests/Displayed title/fails()", report)
                self.assertIn(f"./test --only 'CoreTests/{suite_path}'", report)

    def test_failed_file_scope_case_reruns_only_the_original_function(self):
        from grouped_tests import GroupedTestSuites

        document = {
            "testNodes": [
                {
                    "nodeType": "Unit test bundle",
                    "name": "GroupedLibraryTests",
                    "children": [
                        {
                            "nodeType": "Test Case",
                            "name": "standalone()",
                            "nodeIdentifier": "standalone()",
                            "result": "Failed",
                        }
                    ],
                }
            ]
        }
        inventory = GroupedTestSuites({"CoreTests"}, {"standalone()": "CoreTests"})
        with patch.object(
            GroupedTestSuites, "from_manifest_or_repository", return_value=inventory
        ):
            report = failure_report(document, "/tmp/grouped.xcresult")
        self.assertIn("./test --only 'CoreTests/standalone()'", report)
        self.assertEqual(
            grouped_filters(["CoreTests/standalone()"], inventory),
            ["GroupedLibraryTests/standalone()"],
        )

    def test_discovers_snapshot_bundles(self):
        project = 'name: "WhereUISnapshotTests"\nname: "WhereUISnapshotTests"\nname: "CoreTests"'
        self.assertEqual(snapshot_bundles(project), ["WhereUISnapshotTests"])

    def project_with_bundles(self, leading):
        bundles = list(leading)
        while len(bundles) < 15:
            index = len(bundles)
            bundles.append(
                (f"Dummy{index}Tests", f"Dummy/{index}/Tests", f"Dummy{index}")
            )
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
