import json
from pathlib import Path
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import patch
from Tools.view_layout_runner import MARKER, parse_output, fingerprint, execute


class LayoutRunnerTests(unittest.TestCase):
    def test_rejects_empty_partial_duplicate_and_invalid_runtime_reports(self):
        for output in ("", "runner crashed", MARKER + "\n" + MARKER + "\n", "Class is implemented in both images\n" + MARKER):
            with self.assertRaises(ValueError):
                parse_output(output, "{}")
        with self.assertRaises(ValueError):
            parse_output(MARKER, "{")
        self.assertEqual(parse_output("system log\n" + MARKER + "\n", '{"samples": []}'), {"samples": []})

    def test_fingerprint_changes_for_source_but_not_baseline(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "Tools/ViewLayoutAudit/Runner").mkdir(parents=True)
            for name in ("Package.swift", "Package.resolved", "Project.swift", "Tools/ViewLayoutAudit/registrations.json", "Tools/ViewLayoutAudit/platforms.json"):
                (root / name).write_text("initial")
            before = fingerprint(root)
            (root / "Tools/ViewLayoutAudit/baseline.json").write_text("updated budget")
            self.assertEqual(fingerprint(root), before)
            (root / "Project.swift").write_text("changed settings")
            self.assertNotEqual(fingerprint(root), before)

    def test_execute_rejects_stale_identity_and_preserves_the_report(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "Tools/ViewLayoutAudit/Runner").mkdir(parents=True)
            for name in ("Package.swift", "Package.resolved", "Project.swift", "Tools/ViewLayoutAudit/registrations.json", "Tools/ViewLayoutAudit/platforms.json"):
                (root / name).write_text("fixture")
            products = root / "products"
            (products / "LedgerLayoutAuditCompanion.app").mkdir(parents=True)
            report = {"build": {"configuration": "Debug", "platform": "macOS", "architecture": "arm64", "inputHash": fingerprint(root), "commit": "old", "xcode": "fixture"}, "samples": []}
            def fake_run(argv, **kwargs):
                if argv[0] == "git":
                    return SimpleNamespace(stdout="current\n", returncode=0)
                if argv[0] == "xcodebuild":
                    return SimpleNamespace(stdout="Xcode fixture\nBuild version fixture\n", returncode=0)
                Path(kwargs["env"]["VIEW_LAYOUT_AUDIT_OUTPUT"]).write_text(json.dumps(report))
                kwargs["stdout"].write(MARKER + "\n")
                return SimpleNamespace(returncode=0)
            with patch("Tools.view_layout_runner.subprocess.run", side_effect=fake_run):
                with self.assertRaisesRegex(ValueError, "commit"):
                    execute(root, products, "macOS", "Debug", root / "output", [])
            self.assertTrue((root / "output/report.json").is_file())


if __name__ == "__main__":
    unittest.main()
