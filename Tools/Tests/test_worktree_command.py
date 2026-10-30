"""Exercise cleanup through the public shell command with isolated build caches."""

from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest

from Tools.repository import repository_root


REPOSITORY = repository_root(__file__)


class WorktreeCommandTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="worktree command ü ")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.checkout = self.root / "Stuff with spaces"
        self.outside = self.root / "outside"
        self.bin = self.root / "bin"
        self.derived_data = self.outside / "custom DerivedData"
        for directory in (self.checkout / "Tools", self.bin, self.derived_data):
            directory.mkdir(parents=True)
        (self.checkout / ".git").write_text("gitdir: unused-by-cleanup\n")
        for source in ("worktree", "Tools/worktree_cleanup.py", "Tools/repository.py"):
            shutil.copy2(REPOSITORY / source, self.checkout / source)
        (self.bin / "python3").symlink_to(sys.executable)
        self.simulator_log = self.root / "simulator.log"
        simulator = self.checkout / "simulator"
        simulator.write_text(
            '#!/bin/bash\nprintf "%s\\n" "$*" > "$WORKTREE_SIMULATOR_LOG"\n'
            'exit "${WORKTREE_SIMULATOR_STATUS:-0}"\n'
        )
        simulator.chmod(0o755)
        self.environment = {
            "PATH": f"{self.bin}:/usr/bin:/bin",
            "WORKTREE_SIMULATOR_LOG": str(self.simulator_log),
        }

    def cache(self):
        cache = self.derived_data / "cache"
        cache.mkdir()
        (cache / "info.plist").write_bytes(
            plistlib.dumps({"WorkspacePath": str(self.checkout / "Stuff.xcworkspace")})
        )
        (cache / "product").write_text("compiled")
        return cache

    def run_command(self, *arguments):
        return subprocess.run(
            [str(self.checkout / "worktree"), *arguments],
            cwd=self.outside,
            env=self.environment,
            text=True,
            capture_output=True,
            timeout=20,
        )

    def test_cleanup_from_unrelated_cwd_removes_owned_cache_and_calls_simulator(self):
        cache = self.cache()
        result = self.run_command(
            "--cleanup", "--derived-data-root", str(self.derived_data)
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertFalse(cache.exists())
        self.assertEqual(self.simulator_log.read_text(), "--delete\n")
        self.assertIn("Removed 1 DerivedData directory", result.stderr)

    def test_dry_run_preserves_cache_and_never_calls_simulator(self):
        cache = self.cache()
        result = self.run_command(
            "--cleanup", "--dry-run", "--derived-data-root", "custom DerivedData"
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertEqual((cache / "product").read_text(), "compiled")
        self.assertFalse(self.simulator_log.exists())
        self.assertIn(f"Would remove {cache}", result.stderr)
        self.assertIn("Would run ./simulator --delete", result.stderr)
        self.assertFalse((self.checkout / "Tools/__pycache__").exists())

    def test_prune_never_calls_simulator(self):
        result = self.run_command(
            "--prune-derived-data",
            "--dry-run",
            "--derived-data-root",
            str(self.derived_data),
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertFalse(self.simulator_log.exists())

    def test_bare_cleanup_modes_reach_python_without_empty_array_errors(self):
        # Keep the default-location invocation away from real developer caches.
        python = self.bin / "python3"
        python.unlink()
        python.write_text('#!/bin/bash\nprintf "%s\\n" "$*"\n')
        python.chmod(0o755)
        for mode in ("--prune-derived-data", "--cleanup"):
            with self.subTest(mode=mode):
                result = self.run_command(mode)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(
                    result.stdout, f"-B -m Tools.worktree_cleanup {mode}\n"
                )
                self.assertEqual(result.stderr, "")
                if mode == "--cleanup":
                    self.assertEqual(self.simulator_log.read_text(), "--delete\n")
                else:
                    self.assertFalse(self.simulator_log.exists())

    def test_cache_failure_still_calls_simulator_and_returns_failure(self):
        invalid_root = self.outside / "not a directory"
        invalid_root.write_text("keep")
        result = self.run_command("--cleanup", "--derived-data-root", str(invalid_root))
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertIn("DerivedData cleanup failed", result.stderr)
        self.assertEqual(self.simulator_log.read_text(), "--delete\n")
        self.assertEqual(invalid_root.read_text(), "keep")

    def test_simulator_failure_preserves_child_exit_status_after_cache_cleanup(self):
        self.environment["WORKTREE_SIMULATOR_STATUS"] = "42"
        cache = self.cache()
        result = self.run_command(
            "--cleanup", "--derived-data-root", str(self.derived_data)
        )
        self.assertEqual(result.returncode, 42, result.stderr)
        self.assertFalse(cache.exists())
        self.assertEqual(self.simulator_log.read_text(), "--delete\n")

    def test_help_and_invalid_arguments_do_not_run_dependencies(self):
        (self.bin / "python3").unlink()
        for arguments, status, diagnostic in [
            (("--help",), 0, ""),
            (("--cleanup", "--unknown"), 1, "unknown cleanup option"),
            (("--cleanup", "--derived-data-root"), 1, "requires a path"),
            (("--cleanup", "--derived-data-root", "--dry-run"), 1, "requires a path"),
            (("--check-main", "--dry-run"), 1, "Usage:"),
        ]:
            with self.subTest(arguments=arguments):
                result = self.run_command(*arguments)
                self.assertEqual(result.returncode, status, result.stderr)
                if status:
                    self.assertEqual(result.stdout, "")
                    self.assertIn(diagnostic, result.stderr)
                else:
                    self.assertIn("Usage:", result.stdout)
                    self.assertEqual(result.stderr, "")
                self.assertFalse(self.simulator_log.exists())


if __name__ == "__main__":
    unittest.main()
