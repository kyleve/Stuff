"""Budget policy and discovery/generation contracts, without an Apple SDK."""
import copy
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from Tools.view_layout_audit import LIMIT, probe_cases, select_candidates, validate_report, without_hooks, registry_source


class LayoutAuditTests(unittest.TestCase):
    def setUp(self):
        self.cases = [{"id": "Sample/Card:Card", "path": "Shared/Sample/Sources/Card.swift", "line": 4, "condition": "", "type": "Card", "registration": None, "platforms": ["iOSSimulator"]}]
        self.report = {"build": {"configuration": "Debug", "platform": "iOSSimulator", "architecture": "arm64", "xcode": "fixture", "commit": "fixture"}, "samples": [{"id": self.cases[0]["id"], "status": "measured", "view": {"size": 8, "stride": 8, "alignment": 8}, "body": {"size": LIMIT - 8, "stride": LIMIT - 8, "alignment": 8}}]}
        self.baseline = {"version": 1, "budgets": {}}

    def test_threshold_checks_stride_not_only_size(self):
        self.assertEqual(validate_report(self.report, self.cases, self.baseline), [])
        self.report["samples"][0]["body"]["stride"] = LIMIT
        self.assertIn("exceeds", validate_report(self.report, self.cases, self.baseline)[0])

    def test_baseline_blocks_growth_and_requires_removal_when_fixed(self):
        key = "iOSSimulator/Debug/arm64/Sample/Card:Card/body"
        self.baseline["budgets"][key] = {"stride": LIMIT, "reason": "Existing composition"}
        self.report["samples"][0]["body"]["stride"] = LIMIT
        self.assertEqual(validate_report(self.report, self.cases, self.baseline), [])
        self.report["samples"][0]["body"]["stride"] += 8
        self.assertIn("exceeds", validate_report(self.report, self.cases, self.baseline)[0])
        self.report["samples"][0]["body"]["stride"] = LIMIT - 8
        self.assertIn("resolved", validate_report(self.report, self.cases, self.baseline)[0])

    def test_missing_duplicate_unexpected_and_invalid_reports_fail(self):
        empty = copy.deepcopy(self.report)
        empty["samples"] = []
        self.assertIn("Missing", validate_report(empty, self.cases, self.baseline)[0])
        self.report["samples"] *= 2
        self.assertIn("Duplicate", validate_report(self.report, self.cases, self.baseline)[0])
        self.report["samples"][0]["body"]["size"] = -1
        with self.assertRaises(ValueError):
            validate_report(self.report, self.cases, self.baseline)

    def test_inactive_and_exempt_require_inventory_evidence(self):
        self.report["samples"][0] = {"id": self.cases[0]["id"], "status": "inactive"}
        self.assertTrue(validate_report(self.report, self.cases, self.baseline))
        self.cases[0]["condition"] = "DEBUG"
        self.assertEqual(validate_report(self.report, self.cases, self.baseline), [])
        self.report["samples"][0]["status"] = "exempt"
        self.assertTrue(validate_report(self.report, self.cases, self.baseline))
        self.cases[0]["type"] = None
        self.assertEqual(validate_report(self.report, self.cases, self.baseline), [])

    def test_platform_does_not_allow_ios_records_in_mac_report(self):
        self.report["build"]["platform"] = "macOS"
        self.assertTrue(validate_report(self.report, self.cases, self.baseline))

    def test_local_protocol_conformers_are_discovered(self):
        def declaration(name, bases, generic=False):
            return {"name": name, "bases": bases, "generic": generic, "line": 1, "condition": "", "kind": "struct"}
        raw = {"Shared/Sample/Sources/Card.swift": [declaration("Pane", ["View"], True), declaration("Card", ["Pane"]), declaration("NotAView", ["Hashable"])]}
        selected = select_candidates(raw)
        self.assertEqual([d["name"] for d in next(iter(selected.values()))], ["Pane", "Card"])
        with self.assertRaises(ValueError):
            probe_cases(selected, {})
        registration = {"Sample/Pane": {"reason": "Protocol", "exemption": "Concrete conformers measured"}}
        self.assertEqual(len(probe_cases(selected, registration)), 2)
        registration["Sample/Gone"] = {"reason": "Stale", "types": ["Gone"]}
        with self.assertRaises(ValueError):
            probe_cases(selected, registration)

    def test_generated_block_is_removed_without_changing_source(self):
        original = "struct Card {}\n"
        text = original + "\n// BEGIN GENERATED VIEW LAYOUT AUDIT\ncode\n// END GENERATED VIEW LAYOUT AUDIT\n"
        self.assertEqual(without_hooks(text), original)
        with self.assertRaises(ValueError):
            without_hooks(text + "handwritten code\n")

    def test_registry_never_constructs_a_view_or_evaluates_body(self):
        source = registry_source("Sample", ["probe"])
        self.assertIn("MemoryLayout<T>.stride", source)
        self.assertIn("Layout(V.Body.self)", source)
        self.assertNotIn("V()", source)
        self.assertNotIn(".body", source)

    def test_public_help_works_outside_checkout_with_minimal_path(self):
        command = Path(__file__).resolve().parents[2] / "view-layout-audit"
        result = subprocess.run([str(command), "--help"], cwd="/tmp", env={"PATH": "/usr/bin:/bin"}, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--products", result.stdout)


if __name__ == "__main__":
    unittest.main()
