"""Exercise the shard hydration command against a cold, offline Git LFS checkout."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


COMMAND = Path(__file__).resolve().parents[2] / "snapshot-shards"
POINTER = b"version https://git-lfs.github.com/spec/v1"


class ShardHydrationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="shard hydration ü ")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.seed = self.root / "source"
        self.worker = self.root / "worker"
        self.seed.mkdir()
        self.env = {
            **os.environ,
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": os.devnull,
            "GIT_LFS_SKIP_SMUDGE": "1",
        }
        self.git(self.seed, "init", "-b", "fixture")
        self.git(self.seed, "lfs", "install", "--local")
        (self.seed / ".gitattributes").write_text("*.png filter=lfs -text\n")
        (self.seed / "Project.swift").write_text("""
            unitTests(name: "ModuleSnapshotTests", sources: [
              "Module/SnapshotTests/**", "Additional/SnapshotTests/**",
            ]),
            unitTests(name: "OtherSnapshotTests", sources: ["Other/SnapshotTests/**"]),
        """)
        nested = "Additional/SnapshotTests/Nested ü"
        self.add_suite(nested, "NewTests")
        self.add_suite("Other/SnapshotTests", "NewTests")
        self.add_suite("Module/SnapshotTests", "ProbeTests")
        self.add_suite("Module/SnapshotTests/Two, [special]", "SpecialTests")
        self.selected = [
            f"{nested}/__Snapshots__/NewTests/main.png",
            f"{nested}/__Snapshots__/NewTests/themes/other/a, [b]*.png",
        ]
        self.other = "Other/SnapshotTests/__Snapshots__/NewTests/main.png"
        self.stale = f"{nested}/__Snapshots__/RemovedTests/old.png"
        self.special = (
            "Module/SnapshotTests/Two, [special]/__Snapshots__/SpecialTests/s.png"
        )
        for name in [*self.selected, self.other, self.stale, self.special]:
            path = self.seed / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(name.encode())
        self.git(self.seed, "add", ".")
        self.git(
            self.seed,
            "-c",
            "user.name=Test",
            "-c",
            "user.email=test@example.test",
            "commit",
            "-m",
            "Fixture",
        )
        self.git(self.root, "clone", "--no-local", str(self.seed), str(self.worker))
        self.git(self.worker, "lfs", "install", "--local")
        self.plan = self.root / "plan.json"
        self.plan.write_text('{"formatVersion": 1, "shards": []}')

    def add_suite(self, directory, name):
        source = self.seed / directory / f"{name}.swift"
        source.parent.mkdir(parents=True, exist_ok=True)
        source.write_text(f"struct {name} {{}}\n")

    def git(self, directory, *args):
        return subprocess.run(
            ["git", *args],
            cwd=directory,
            env=self.env,
            capture_output=True,
            check=True,
        )

    def hydrate(self, *suites):
        assignment = self.root / "assignment.txt"
        assignment.write_text("".join(f"{suite}\n" for suite in suites))
        return subprocess.run(
            [
                COMMAND,
                "--plan",
                self.plan,
                "hydrate",
                "--repo",
                self.worker,
                "--assignment",
                assignment,
            ],
            cwd=self.root,
            env=self.env,
            capture_output=True,
            text=True,
        )

    def test_fetches_only_the_assigned_source_and_nested_references(self):
        result = self.hydrate(
            "ModuleSnapshotTests/NewTests", "ModuleSnapshotTests/ProbeTests"
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Verified 2 assigned", result.stdout)
        for name in self.selected:
            self.assertEqual((self.worker / name).read_bytes(), name.encode())
        for name in [self.other, self.stale, self.special]:
            self.assertTrue((self.worker / name).read_bytes().startswith(POINTER))
        objects = self.worker / ".git/lfs/objects"
        self.assertEqual(sum(path.is_file() for path in objects.rglob("*")), 2)

    def test_unsupported_directory_pattern_uses_the_reported_fallback(self):
        result = self.hydrate("ModuleSnapshotTests/SpecialTests")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("fetching snapshot references for all suites", result.stderr)
        self.assertIn("Verified 1 assigned", result.stdout)
        self.assertEqual(
            (self.worker / self.special).read_bytes(), self.special.encode()
        )

    def test_empty_or_invalid_assignments_do_not_fetch_and_fetch_errors_propagate(self):
        self.git(self.worker, "remote", "set-url", "origin", str(self.root / "absent"))
        for assignment in [[], ["ModuleSnapshotTests/ProbeTests"]]:
            result = self.hydrate(*assignment)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("Verified 0 assigned", result.stdout)
        unknown = self.hydrate("ModuleSnapshotTests/NewTests", "Missing/Unknown")
        self.assertNotEqual(unknown.returncode, 0)
        self.assertIn("unknown snapshot suites", unknown.stderr)
        failed = self.hydrate("ModuleSnapshotTests/NewTests")
        self.assertNotEqual(failed.returncode, 0)
        self.assertNotIn("Verified", failed.stdout)

    def test_verification_detects_an_unresolved_selected_pointer(self):
        # LFS preserves a locally modified pointer even after a successful pull.
        path = self.worker / self.selected[0]
        path.write_bytes((self.worker / self.other).read_bytes())
        result = self.hydrate("ModuleSnapshotTests/NewTests")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(f"remains a Git LFS pointer: {self.selected[0]}", result.stderr)
