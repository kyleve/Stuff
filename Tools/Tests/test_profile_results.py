from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from profile_results import build_report, test_report


class ProfileResultsTests(unittest.TestCase):
    def test_build_report_orders_phases_and_typecheck_sites(self):
        log = """SwiftCompile (2 tasks) | 4.0 seconds
Link (1 task) | 1.0 seconds
/tmp/repo/Where/Feature/File.swift:2:3: warning: expression took 250ms to type-check
/tmp/repo/Shared/Core/File.swift:4:5: warning: function took 125ms to type-check
"""

        report = build_report(log, 100)

        self.assertLess(report.index("SwiftCompile"), report.index("Link"))
        self.assertIn("80%  SwiftCompile", report)
        self.assertLess(report.index("250ms"), report.index("125ms"))
        self.assertIn("Where/Feature/File.swift:2:3", report)

    def test_test_report_merges_documents_and_excludes_skipped_cases(self):
        documents = [
            self.document("CoreTests", "fast()", "Passed", 0.05),
            self.document("UITests", "slow()", "Failed", 0.5),
            self.document("UITests", "skipped()", "Skipped", 10),
        ]

        report = test_report(documents, top=2, threshold=0.1)

        self.assertIn("2 tests, summed self-time 0.55s", report)
        self.assertLess(report.index("slow()"), report.index("fast()"))
        self.assertNotIn("skipped()", report)
        self.assertIn("UITests (1 tests)", report)
        self.assertIn("1 test(s) at/over the 0.1s threshold", report)

    def document(self, bundle, name, result, duration):
        return {
            "testNodes": [
                {
                    "nodeType": "Unit test bundle",
                    "name": bundle,
                    "children": [
                        {
                            "nodeType": "Test Case",
                            "name": name,
                            "result": result,
                            "durationInSeconds": duration,
                        }
                    ],
                }
            ]
        }


if __name__ == "__main__":
    unittest.main()
