"""Exercise the PR count command against real, isolated Git histories."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from Tools.repository import repository_root


class PRChangeCountsTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="pr counts ü ")
        self.addCleanup(temporary.cleanup)
        self.outside = Path(temporary.name)
        self.checkout = self.outside / "checkout ü"
        (self.checkout / "Tools").mkdir(parents=True)
        self.environment = {
            **os.environ,
            "GIT_CONFIG_GLOBAL": os.devnull,
            "GIT_CONFIG_NOSYSTEM": "1",
        }
        for name in (
            "pr-change-counts",
            "Tools/pr_change_counts.py",
            "Tools/repository.py",
        ):
            shutil.copy2(repository_root(__file__) / name, self.checkout / name)
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.name", "PR Count Test")
        self.git("config", "user.email", "test@example.test")

    def git(self, *args):
        return subprocess.check_output(
            ["git", *args], cwd=self.checkout, env=self.environment, text=True
        ).strip()

    def write(self, name, contents):
        path = self.checkout / name
        path.parent.mkdir(parents=True, exist_ok=True)
        if isinstance(contents, str):
            path.write_text(contents, encoding="utf-8")
        else:
            path.write_bytes(contents)

    def commit(self):
        self.git("add", "--all")
        self.git("commit", "-qm", "Fixture commit")
        return self.git("rev-parse", "HEAD")

    def run_command(self, *args, environment=None):
        return subprocess.run(
            [self.checkout / "pr-change-counts", *args],
            cwd=self.outside,
            env=self.environment if environment is None else environment,
            text=True,
            capture_output=True,
            timeout=15,
        )

    def test_merge_base_categories_and_snapshot_moves(self):
        snapshots = "App/SnapshotTests/__Snapshots__/Example"
        self.write(".gitattributes", "**/__Snapshots__/**/*.png diff=lfs\n")
        self.write("App/Sources/Test.swift", "keep\nold\n")
        self.write("remove.md", "remove this\nand this\nand this too\n")
        self.write(f"{snapshots}/changed.png", b"\0before")
        self.write(f"{snapshots}/removed.png", b"\0delete")
        self.write(f"{snapshots}/renamed.png", b"\0rename")
        self.write(f"{snapshots}/move-out.png", b"\0move out")
        self.write("App/Resources/move-in.png", b"\0move in")
        base = self.commit()
        self.write("base-branch-only.md", "changes on main\n")
        self.git("update-ref", "refs/remotes/origin/main", self.commit())
        self.git("switch", "-qc", "topic", base)

        self.write("App/Sources/Test.swift", "keep\nnew\nextra\n")
        self.write("App/Tests/Fixtures/values.json", "{}\n")
        self.write("App/Resources/values.json", "{}\n")
        self.write("App/Resources/other.png", b"\0other asset")
        self.write(".github/workflows/check.yml", "name: Check\n")
        self.write("Tools/example.py", "enabled = True\n")
        self.write("other.unknown", "other change\n")
        self.write("guide\twith spaces\nand ü.MARKDOWN", "new documentation\n")
        self.write(f"{snapshots}/changed.png", b"\0after")
        self.write(
            f"{snapshots}/added.png",
            f"version https://git-lfs.github.com/spec/v1\noid sha256:{'a' * 64}\nsize 10\n",
        )
        (self.checkout / "remove.md").unlink()
        (self.checkout / f"{snapshots}/removed.png").unlink()
        self.git("mv", f"{snapshots}/renamed.png", f"{snapshots}/renamed ü.png")
        self.git("mv", f"{snapshots}/move-out.png", "App/Resources/moved-out.png")
        self.git("mv", "App/Resources/move-in.png", f"{snapshots}/moved-in.png")
        head = self.commit()

        expected = (
            "| Category | Files | Lines added | Lines deleted | Binary files |\n"
            "| --- | ---: | ---: | ---: | ---: |\n"
            "| Markdown | 2 | 1 | 3 | 0 |\n"
            "| App code | 1 | 2 | 1 | 0 |\n"
            "| Resources | 2 | 1 | 0 | 1 |\n"
            "| Tests | 1 | 1 | 0 | 0 |\n"
            "| Configuration | 1 | 1 | 0 | 0 |\n"
            "| Tooling | 1 | 1 | 0 | 0 |\n"
            "| Other | 1 | 1 | 0 | 0 |\n"
            "| Snapshots added | 2 | 0 | 0 | 2 |\n"
            "| Snapshots removed | 2 | 0 | 0 | 2 |\n"
            "| Snapshots changed | 2 | 0 | 0 | 2 |\n"
            "| **Total** | 15 | 8 | 4 | 7 |\n"
        )
        self.git("switch", "-q", "main")
        self.assert_report(expected, "--base", "main", "--head", head)
        self.git("switch", "-q", "topic")
        self.write("staged.md", "staged change\n")
        self.git("add", "staged.md")
        self.write("App/Sources/Test.swift", "unstaged change\n")
        self.write(".gitattributes", "")
        self.assert_report(expected)

    def test_empty_diff_and_invalid_revision(self):
        self.commit()
        self.assert_report(
            "| Category | Files | Lines added | Lines deleted | Binary files |\n"
            "| --- | ---: | ---: | ---: | ---: |\n"
            "| **Total** | 0 | 0 | 0 | 0 |\n",
            "--base",
            "HEAD",
        )
        result = self.run_command("--base=--invalid-ref")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertIn("cannot resolve Git ref '--invalid-ref'", result.stderr)

    def test_help_needs_no_git(self):
        bin_directory = self.outside / "bin"
        bin_directory.mkdir()
        (bin_directory / "python3").symlink_to(shutil.which("python3"))
        (bin_directory / "dirname").symlink_to(shutil.which("dirname"))
        result = self.run_command(
            "--help", environment={**self.environment, "PATH": str(bin_directory)}
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--base", result.stdout)
        self.assertEqual(result.stderr, "")

    def assert_report(self, expected, *args):
        result = self.run_command(*args)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        self.assertEqual(result.stdout, expected)
