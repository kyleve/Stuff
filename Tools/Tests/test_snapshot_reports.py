import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from snapshot_reports import difference_report, timing_report


class SnapshotReportsTests(unittest.TestCase):
    def test_timing_report_shares_common_summary_and_optional_detail(self):
        rows = [
            {
                "id": "Suite/first",
                "total": 2.0,
                "phases": {"render": 1.5, "intrinsicMeasure": 0.5},
                "settlePasses": 2,
                "sizing": "fullContent",
                "measurementReadiness": "ready",
                "captureSettle": "stable",
            },
            {
                "id": "Suite/second",
                "total": 1.0,
                "phases": {"render": 1.0},
                "settlePasses": 1,
                "sizing": "fixed",
                "measurementReadiness": "ready",
                "captureSettle": "stable",
            },
        ]

        concise = timing_report(rows, detailed=False, empty_message="none")
        detailed = timing_report(rows, detailed=True, empty_message="none")

        self.assertIn("2 captures, 3.0s total, 1.500s per image", concise)
        self.assertIn("render", concise)
        self.assertIn("settle passes: min 1, max 2, mean 1.5", concise)
        self.assertNotIn("measurement readiness", concise)
        self.assertIn("measurement readiness", detailed)
        self.assertIn("0.50s  ready (2 captures)", detailed)

    def test_difference_report_orders_real_differences_and_hides_recording_misses(self):
        rows = [
            {
                "outcome": "referenceMissing",
                "reference": "missing.png",
            },
            {
                "outcome": "differs",
                "maxChannelDelta": 40,
                "differingPixels": 2,
                "differingFraction": 0.25,
                "region": [1, 2, 3, 4],
                "reference": "/tmp/__Snapshots__/Suite/image.png",
            },
        ]

        report = difference_report(rows, is_recording=True)

        self.assertIn("1 capture(s)", report)
        self.assertIn("40", report)
        self.assertIn("Suite/image.png", report)
        self.assertNotIn("referenceMissing", report)

    def test_empty_reports_preserve_public_messages(self):
        self.assertEqual(
            timing_report([], detailed=False, empty_message="no timing lines found"),
            "  (no timing lines found)",
        )
        self.assertEqual(
            difference_report([], is_recording=False),
            "  Every capture matched its reference byte for byte.",
        )


if __name__ == "__main__":
    unittest.main()
