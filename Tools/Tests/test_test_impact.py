import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from test_impact import make_plan, tracked_blobs, write_json
from Fixtures.test_impact_fixtures import metadata

ROOT = Path(__file__).resolve().parents[2]


class ImpactCommandTests(unittest.TestCase):
    def test_help_needs_no_xcode_and_works_from_another_directory(self):
        with tempfile.TemporaryDirectory(prefix="impact space é ") as directory:
            result = subprocess.run([str(ROOT / "test"), "--impact", "plan", "--help"], cwd=directory,
                                    env={**os.environ, "PATH": "/usr/bin:/bin"}, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("--base-metadata", result.stdout)
            self.assertEqual(list(Path(directory).iterdir()), [])

    def test_invalid_args_fail_before_tools(self):
        result = subprocess.run([str(ROOT / "test"), "--impact", "plan", "--mode", "invalid"],
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("xcodebuild", result.stderr)

    def test_merge_base_handles_multiple_commits_and_deletions(self):
        with tempfile.TemporaryDirectory(prefix="impact git é ") as directory:
            root = Path(directory)
            def git(*args):
                return subprocess.check_output(["git", *args], cwd=root, text=True).strip()
            git("init", "-q")
            git("config", "user.name", "Test")
            git("config", "user.email", "test@example.invalid")
            git("config", "commit.gpgsign", "false")
            git("config", "core.hooksPath", "/dev/null")
            (root / "UI").mkdir()
            (root / "UI/Card.swift").write_text("old")
            git("add", ".")
            git("commit", "-qm", "base")
            base_sha = git("rev-parse", "HEAD")
            base = metadata(base_sha)
            base["blobs"] = tracked_blobs(root=root)
            (root / "UI/Card.swift").unlink()
            git("add", "-u")
            git("commit", "-qm", "delete")
            (root / "README.md").write_text("docs")
            git("add", ".")
            git("commit", "-qm", "docs")
            head = metadata(git("rev-parse", "HEAD"))
            head["blobs"] = tracked_blobs(root=root)
            write_json(root / "head.json", head)
            write_json(root / "base.json", base)
            output = root / "plan.json"
            plan = make_plan(root / "head.json", base_sha, "HEAD", "target", output, root / "base.json", root)
            self.assertEqual(plan["changed"], ["README.md", "UI/Card.swift"])
            self.assertEqual(plan["mergeBase"], base_sha)
            self.assertEqual(json.loads(output.read_text()), plan)
            missing = make_plan(root / "head.json", "absent", "HEAD", "target", output, root=root)
            self.assertEqual(len(missing["selectedBundles"]), 3)
            head["dirty"] = True
            write_json(root / "head.json", head)
            with self.assertRaisesRegex(ValueError, "uncommitted"):
                make_plan(root / "head.json", base_sha, "HEAD", "snapshot", output, root=root)
