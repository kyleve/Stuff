import contextlib
import io
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from Tools import ci_changes
from Tools.Tests.ci_test_support import GitRepository


class CIChangesTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="CI changes ü ")
        self.addCleanup(temporary.cleanup)
        self.repo = GitRepository(temporary.name)

    def decision(self, **overrides):
        arguments = {
            "event": "pull_request",
            "base": self.repo.base,
            "head": self.repo.git("rev-parse", "HEAD"),
            "force": False,
        }
        arguments.update(overrides)
        return ci_changes.classify_changes(self.repo.root, **arguments)

    def test_add_edit_delete_and_rename_documentation(self):
        self.repo.git("mv", "README.md", "Renamed.markdown")
        self.repo.write("nested/NEW.MD", "New docs\n")
        self.repo.write("Sources/Feature/AGENTS.md", "Source rules\n")
        self.repo.commit()
        self.assertTrue(self.decision().docs_only)
        self.repo.write("Renamed.markdown", "Revised docs\n")
        self.repo.git("rm", "nested/NEW.MD")
        self.repo.commit()
        self.assertTrue(self.decision().docs_only)

    def test_mixed_changes_run_ci(self):
        self.repo.write("README.md", "Revised docs\n")
        self.repo.write("app.py", "changed = True\n")
        self.repo.commit()
        self.assertFalse(self.decision().docs_only)

    def test_latest_documentation_commit_cannot_hide_earlier_code(self):
        self.repo.write("app.py", "changed = True\n")
        self.repo.commit()
        self.repo.write("README.md", "Revised docs\n")
        self.repo.commit()
        self.assertFalse(self.decision().docs_only)

    def test_renaming_code_to_markdown_runs_ci(self):
        self.repo.git("mv", "app.py", "app.md")
        self.repo.commit()
        self.assertFalse(self.decision().docs_only)

    def test_renaming_markdown_to_code_runs_ci(self):
        self.repo.git("mv", "README.md", "README.py")
        self.repo.commit()
        self.assertFalse(self.decision().docs_only)

    def test_deleted_code_runs_ci(self):
        self.repo.git("rm", "app.py")
        self.repo.commit()
        self.assertFalse(self.decision().docs_only)

    def test_base_branch_changes_are_not_part_of_the_pr(self):
        self.repo.write("README.md", "Revised docs\n")
        head = self.repo.commit()
        self.repo.git("switch", "main")
        self.repo.write("app.py", "base_only_change = True\n")
        base = self.repo.commit()
        self.assertTrue(self.decision(base=base, head=head).docs_only)
        self.repo.git("switch", "topic")
        self.repo.git("merge", "main", "--no-edit")
        self.assertTrue(self.decision(base=base).docs_only)

    def test_diff_is_not_truncated_at_api_path_limits(self):
        for index in range(3100):
            self.repo.write(f"docs/{index}.md", "Docs\n")
        self.repo.commit()
        self.assertTrue(self.decision().docs_only)
        self.repo.write("z-last.py", "code = True\n")
        self.repo.commit()
        self.assertFalse(self.decision().docs_only)

    def test_spaces_unicode_and_newlines_in_paths(self):
        self.repo.write("docs/guide ü\nwith spaces.markdown", "Docs\n")
        self.repo.commit()
        self.assertTrue(self.decision().docs_only)
        self.repo.write("docs/README.md\ncode.py", "code = True\n")
        self.repo.commit()
        self.assertFalse(self.decision().docs_only)

    def test_empty_diff_runs_ci(self):
        self.assertFalse(self.decision().docs_only)

    def test_executable_markdown_runs_ci(self):
        (self.repo.root / "README.md").chmod(0o755)
        self.repo.commit()
        self.assertFalse(self.decision().docs_only)

    def test_deleting_executable_markdown_runs_ci(self):
        (self.repo.root / "README.md").chmod(0o755)
        base = self.repo.commit()
        self.repo.git("rm", "README.md")
        self.repo.commit()
        self.assertFalse(self.decision(base=base).docs_only)

    def test_symlink_named_markdown_runs_ci(self):
        (self.repo.root / "linked.md").symlink_to("app.py")
        self.repo.commit()
        self.assertFalse(self.decision().docs_only)

    def test_markdown_inputs_run_ci(self):
        for path in (
            "Where/App/Resources/help.md",
            "Tools/Tests/Fixtures/input.md",
            "Tests/__Snapshots__/reference.md",
            "Site/src/pages/about.md",
            "Site/public/help.markdown",
        ):
            with self.subTest(path=path):
                self.assertFalse(ci_changes.documentation_path(path))
        self.repo.write("Where/App/Resources/help.md", "Rendered copy\n")
        self.repo.commit()
        self.assertFalse(self.decision().docs_only)

    def test_main_manual_and_unknown_events_always_run_ci(self):
        self.repo.write("README.md", "Revised docs\n")
        self.repo.commit()
        for event in ("push", "workflow_dispatch", "api", "", "schedule"):
            with self.subTest(event=event):
                self.assertFalse(self.decision(event=event).docs_only)
        self.assertFalse(self.decision(force=True).docs_only)

    def test_missing_or_invalid_history_defaults_to_ci_with_a_reason(self):
        for base in ("", "<nil>", "--help", "f" * 40):
            with self.subTest(base=base):
                decision = self.decision(base=base)
                self.assertFalse(decision.docs_only)
                self.assertIn("Cannot classify", decision.reason)

    def test_shallow_clone_cannot_silently_skip_ci(self):
        self.repo.write("README.md", "Revised docs\n")
        head = self.repo.commit()
        with tempfile.TemporaryDirectory() as destination:
            clone = Path(destination) / "shallow"
            self.repo.git("clone", "--depth=1", self.repo.root.as_uri(), str(clone))
            decision = ci_changes.classify_changes(
                clone,
                event="pull_request",
                base=self.repo.base,
                head=head,
                force=False,
            )
            self.assertFalse(decision.docs_only)
            self.assertIn("Cannot classify", decision.reason)

    def test_git_timeout_defaults_to_ci(self):
        with patch.object(
            ci_changes.subprocess,
            "run",
            side_effect=subprocess.TimeoutExpired("git", 60),
        ):
            decision = ci_changes.classify_changes(
                self.repo.root,
                event="pull_request",
                base=self.repo.base,
                head=self.repo.base,
                force=False,
            )
        self.assertFalse(decision.docs_only)
        self.assertIn("TimeoutExpired", decision.reason)

    def test_malformed_diff_cannot_approve_a_skip(self):
        for raw in (b"record", b"record\0", b"record\0README.md\0"):
            with self.subTest(raw=raw):
                with self.assertRaises(ValueError):
                    ci_changes.documentation_diff(raw)

    def test_command_emits_github_output_and_diagnostic_separately(self):
        self.repo.write("README.md", "Revised docs\n")
        head = self.repo.commit()
        result = subprocess.run(
            [
                sys.executable,
                "-m",
                "Tools.ci_changes",
                "--event",
                "pull_request",
                "--base",
                self.repo.base,
                "--head",
                head,
            ],
            cwd=self.repo.root,
            capture_output=True,
            text=True,
            env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"},
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "docs_only=true\n")
        self.assertIn("complete PR diff", result.stderr)

    def test_command_reports_full_ci_for_missing_history(self):
        stdout, stderr = io.StringIO(), io.StringIO()
        with (
            patch.object(ci_changes, "repository_root", return_value=self.repo.root),
            contextlib.redirect_stdout(stdout),
            contextlib.redirect_stderr(stderr),
        ):
            status = ci_changes.main(
                ["--event", "pull_request", "--base", "", "--head", ""]
            )
        self.assertEqual(status, 0)
        self.assertEqual(stdout.getvalue(), "docs_only=false\n")
        self.assertIn("Running full CI", stderr.getvalue())
