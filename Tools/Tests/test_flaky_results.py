from datetime import datetime, timezone
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from flaky_results import (
    analyze_suite_documents,
    console_report,
    flaky_rows,
    markdown_report,
    tight_counts,
)


class FlakyResultsTests(unittest.TestCase):
    def test_analyzes_suite_runs_with_stable_only_testing_identifiers(self):
        documents = [
            self.document("Passed"),
            self.document("Failed"),
        ]

        stats = analyze_suite_documents(documents)

        self.assertEqual(
            stats["CoreTests/ValueTests/works()"],
            {
                "bundle": "CoreTests",
                "name": "works()",
                "fails": 1,
                "seen": 2,
            },
        )

    def test_tight_counts_prefers_iterations_then_falls_back_to_summary(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "tight_1.tests.json").write_text(
                json.dumps(
                    {
                        "testNodes": [
                            self.case("Passed"),
                            self.case("Failed"),
                            self.case("Passed"),
                        ]
                    }
                )
            )
            (root / "tight_1.summary.json").write_text(
                json.dumps({"failedTests": 9, "passedTests": 1})
            )
            (root / "tight_2.tests.json").write_text(
                json.dumps({"testNodes": [self.case("Failed")]})
            )
            (root / "tight_2.summary.json").write_text(
                json.dumps({"failedTests": 2, "passedTests": 3})
            )

            self.assertEqual(tight_counts(root, "1"), (1, 3))
            self.assertEqual(tight_counts(root, "2"), (2, 5))

    def test_reports_only_tests_with_both_passes_and_failures(self):
        suite = {
            "flaky": {"bundle": "CoreTests", "name": "flaky()", "fails": 1, "seen": 2},
            "broken": {"bundle": "CoreTests", "name": "broken()", "fails": 2, "seen": 2},
            "passing": {"bundle": "CoreTests", "name": "passing()", "fails": 0, "seen": 2},
        }

        rows = flaky_rows(
            suite,
            {"flaky": (1, 4), "broken": (4, 4), "passing": (0, 4)},
            suite_runs=2,
        )

        self.assertEqual([row["id"] for row in rows], ["flaky"])
        self.assertEqual(rows[0]["flake_rate"], 0.375)
        self.assertIn("37.5%", console_report(rows, top=1))

        markdown = markdown_report(
            rows,
            top=1,
            suite_runs=2,
            iterations=4,
            relaunch="YES",
            device="iPhone 17",
            os_version="27.0",
            generated_at=datetime(2026, 8, 17, 12, 0, tzinfo=timezone.utc),
        )
        self.assertIn("2026-08-17T12:00:00Z", markdown)
        self.assertIn("| `flaky` | CoreTests | 1/2 | 1/4 | 38% |", markdown)

    def document(self, result):
        return {
            "testNodes": [
                {
                    "nodeType": "Unit test bundle",
                    "name": "CoreTests",
                    "children": [
                        {
                            "nodeType": "Test Suite",
                            "name": "ValueTests",
                            "children": [self.case(result)],
                        }
                    ],
                }
            ]
        }

    def case(self, result):
        return {
            "nodeType": "Test Case",
            "name": "works()",
            "nodeIdentifier": "ValueTests/works()",
            "result": result,
        }


if __name__ == "__main__":
    unittest.main()
