"""Exercise the inventory gate against a real PR diff and snapshot plan."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from Tools.Tests.ci_test_support import GitRepository


ROOT = Path(__file__).resolve().parents[2]
GATE = ".circleci/validate_snapshot_inventory.sh"
SOURCE = "Module/SnapshotTests/Nested/ExampleTests.swift"
SUITE = "ModuleSnapshotTests/ExampleTests"


class SnapshotInventoryTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="snapshot inventory ")
        self.addCleanup(temporary.cleanup)
        self.repo = GitRepository(temporary.name)
        self.workdir = self.repo.root / "test-output-ios"
        self.workdir.mkdir()
        for name in (GATE, "snapshot-shards", "Tools/snapshot_shards.py"):
            shutil.copy(ROOT / name, self.repo.root / name)
        self.repo.write(".gitignore", "test-output-ios/\n__pycache__/\n")
        self.repo.write(
            "Project.swift",
            'unitTests(name: "ModuleSnapshotTests", sources: ["Module/SnapshotTests/**"]),\n',
        )
        self.repo.write(SOURCE, "struct ExampleTests {}\n")
        self.repo.write(
            ".circleci/snapshot-shards.json",
            json.dumps(
                {"formatVersion": 1, "shards": [{"index": 0, "suites": [SUITE]}]}
            ),
        )
        self.repo.write(
            "test",
            "#!/bin/sh\n"
            'printf "%s\\n" "$@" > "$TEST_WORKDIR/test-arguments"\n'
            'if [ "$ENUMERATION_STATUS" -ne 0 ]; then exit "$ENUMERATION_STATUS"; fi\n'
            'printf "%s\\n" "$ENUMERATED_SUITE" > "$TEST_WORKDIR/suites.txt"\n',
        )
        (self.repo.root / "test").chmod(0o755)
        self.repo.git("update-ref", "refs/remotes/origin/main", self.repo.commit())

    def change(self, path):
        with (self.repo.root / path).open("a") as output:
            output.write("\n")
        self.repo.commit()

    def validate(self, suite=SUITE, status=0):
        return subprocess.run(
            ["bash", GATE],
            cwd=self.repo.root,
            env={
                **os.environ,
                "TEST_WORKDIR": str(self.workdir),
                "CIRCLE_WORKING_DIRECTORY": str(self.repo.root),
                "ENUMERATED_SUITE": suite,
                "ENUMERATION_STATUS": str(status),
            },
            capture_output=True,
            text=True,
        )

    def test_unrelated_change_skips_xcode(self):
        self.change(".circleci/continue.yml")
        result = self.validate(status=13)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.workdir / "test-arguments").exists())

    def test_changed_gate_project_and_snapshot_sources_enumerate_the_whole_scheme(self):
        for path in (GATE, "Project.swift", SOURCE):
            with self.subTest(path=path):
                self.repo.git("update-ref", "refs/remotes/origin/main", "HEAD")
                self.change(path)
                result = self.validate()
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("matches the deterministic plan", result.stdout)
                self.assertEqual(
                    (self.workdir / "test-arguments").read_text().splitlines(),
                    [
                        "--snapshots",
                        "--shared",
                        "--os",
                        "27.2",
                        "--test-artifacts",
                        str(self.repo.root / "ci-test-build"),
                        "--enumerate-suites",
                        str(self.workdir / "suites.txt"),
                        "--skip-architecture",
                    ],
                )

    def test_enumeration_failure_stops_before_comparing(self):
        self.change("Project.swift")
        result = self.validate(status=13)
        self.assertEqual(result.returncode, 13, result.stderr)
        self.assertFalse((self.workdir / "suites.txt").exists())

    def test_drift_fails_with_both_missing_and_stale_suite_names(self):
        self.change(SOURCE)
        result = self.validate(suite="ModuleSnapshotTests/UnexpectedTests")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(
            "plan omits ['ModuleSnapshotTests/UnexpectedTests']", result.stderr
        )
        self.assertIn(f"plan contains stale suites ['{SUITE}']", result.stderr)
