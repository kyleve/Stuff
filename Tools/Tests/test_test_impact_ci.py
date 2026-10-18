from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from test_impact import load, write_json
from test_impact_ci import evidence, prepare, worker
from test_impact_selection import select
from Fixtures.test_impact_fixtures import metadata


class ImpactCITests(unittest.TestCase):
    def test_plan_cache_is_unique_per_workflow(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with patch("test_impact_ci.ROOT", root), patch("test_impact_ci.revision", return_value="head"), patch(
                "test_impact_ci.git", return_value="base"
            ), patch("test_impact_ci.tool_key", return_value="tools"), patch.dict("os.environ", {"CIRCLE_WORKFLOW_ID": "one"}):
                prepare("snapshot", "main", None)
                first = (root / ".build/test-impact/run-key").read_text()
                with patch.dict("os.environ", {"CIRCLE_WORKFLOW_ID": "two"}):
                    prepare("snapshot", "main", None)
                self.assertNotEqual(first, (root / ".build/test-impact/run-key").read_text())

    def test_normal_full_and_shadow_modes_never_filter(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            assignment = root / "assigned.txt"
            assignment.write_text("Bundle/A\nBundle/B\n")
            output = root / "selected.txt"
            for mode in ("off", "full", "shadow"):
                with patch("test_impact_ci.environment") as env:
                    worker(mode, "snapshot", assignment, output)
                    self.assertEqual(output.read_bytes(), assignment.read_bytes())
                    env.assert_not_called()

    def test_missing_plan_fails_and_empty_selected_shard_is_explicit(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            state = root / ".build/test-impact"
            state.mkdir(parents=True)
            (state / "run-key").write_text("key")
            head = metadata()
            plan = select(head, metadata("base"), ["UI/Card.swift"], "snapshot")
            assignment = root / "assigned.txt"
            assignment.write_text("UISnapshotTests/OtherTests\n")
            output = root / "selected.txt"
            with patch("test_impact_ci.ROOT", root), patch("test_impact_ci.revision", return_value="head"), patch(
                "test_impact_ci.environment", return_value=head["environment"]
            ):
                with self.assertRaises(FileNotFoundError):
                    worker("snapshot", "snapshot", assignment, output)
                self.assertFalse(output.exists())
                write_json(state / "plans/key/snapshot.json", plan)
                worker("snapshot", "snapshot", assignment, output)
                self.assertEqual(output.read_text(), "")
                worker("snapshot", "unit", None, output)
                self.assertEqual(output.read_text(), "UITests\n")

    def test_evidence_binds_artifacts_to_full_workflow_and_revision(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            junit = root / "results.xml"
            junit.write_text("<testsuite/>")
            output = root / "evidence.json"
            with patch("test_impact_ci.revision", return_value="head"), patch(
                "test_impact_ci.environment", return_value={"xcode": "pinned"}
            ), patch.dict("os.environ", {"CIRCLE_WORKFLOW_ID": "workflow", "CIRCLE_BUILD_URL": "job"}):
                evidence("shadow", root, output)
            saved = load(output)
            self.assertEqual(saved["revision"], "head")
            self.assertEqual(saved["workflowID"], "workflow")
            self.assertEqual(saved["junit"][0]["path"], "results.xml")
            self.assertEqual(len(saved["junit"][0]["sha256"]), 64)
