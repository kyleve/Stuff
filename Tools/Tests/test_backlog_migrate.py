"""Public command and source-revision safeguards."""

import contextlib
import io
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from backlog_test_support import manifest as sample_manifest
import backlog_migrate as migration


class MigrationTests(unittest.TestCase):
    def make_repo(self, directory):
        root = Path(directory)
        subprocess.run(["git", "init", "-q", str(root)], check=True)
        (root / "TODOs.md").write_text(
            "# Open issues\n- fix: A fault\n# Completed issues\n- fix: Old fault\n"
        )
        (root / "INBOX.md").write_text("# Open\n\n# Triaged\n")
        subprocess.run(["git", "-C", str(root), "add", "."], check=True)
        subprocess.run(
            [
                "git",
                "-C",
                str(root),
                "-c",
                "user.name=Test",
                "-c",
                "user.email=test@example.com",
                "commit",
                "-qm",
                "Fixture",
            ],
            check=True,
        )
        return root

    def test_source_changes_block_apply_and_manifest_tampering_fails(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = self.make_repo(temporary)
            data = migration.inventory(root, "HEAD", {})
            migration.validate(root, data, True)
            data["entries"][0]["body"] = "lost original evidence"
            with self.assertRaisesRegex(ValueError, "differs from source"):
                migration.validate(root, data, True)
            data = migration.inventory(root, "HEAD", {})
            (root / "TODOs.md").write_text("changed")
            with self.assertRaisesRegex(ValueError, "Source changed"):
                migration.validate(root, data, True)

    def test_deleted_sources_can_be_verified_from_git_but_not_applied(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = self.make_repo(temporary)
            data = migration.inventory(root, "HEAD", {})
            (root / "TODOs.md").unlink()
            (root / "INBOX.md").unlink()
            migration.validate(root, data, False)
            with self.assertRaisesRegex(ValueError, "missing"):
                migration.validate(root, data, True)

    def test_dry_run_has_no_network_or_file_writes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = self.make_repo(temporary)
            path = root / "manifest.json"
            with (
                patch.object(migration, "ROOT", root),
                patch.object(
                    migration, "Linear", side_effect=AssertionError("Network forbidden")
                ),
                contextlib.redirect_stdout(io.StringIO()),
            ):
                self.assertEqual(
                    migration.main(["inventory", "--dry-run", "--manifest", str(path)]),
                    0,
                )
                self.assertFalse(path.exists())
                migration.save_manifest(path, migration.inventory(root, "HEAD", {}))
                before = path.read_bytes()
                self.assertEqual(
                    migration.main(["apply", "--dry-run", "--manifest", str(path)]), 0
                )
                self.assertEqual(before, path.read_bytes())

    def test_atomic_checkpoint_retains_previous_file_on_replace_failure(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "manifest.json"
            path.write_text("original")
            with patch.object(migration.os, "replace", side_effect=OSError("failure")):
                with self.assertRaises(OSError):
                    migration.save_manifest(path, sample_manifest())
            self.assertEqual(path.read_text(), "original")
            self.assertEqual(len(list(path.parent.iterdir())), 1)

    def test_cli_help_and_bad_arguments_from_unrelated_unicode_directory(self):
        command = migration.ROOT / "backlog-migrate"
        with tempfile.TemporaryDirectory(prefix="backlog ü ") as temporary:
            result = subprocess.run(
                [str(command), "--help"], cwd=temporary, capture_output=True, text=True
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("inventory", result.stdout)
            result = subprocess.run(
                [str(command), "apply", "--limit", "0"],
                cwd=temporary,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 2)
            self.assertEqual(list(Path(temporary).iterdir()), [])

    def test_inventory_refuses_to_discard_new_inbox_notes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = self.make_repo(temporary)
            data = migration.inventory(root, "HEAD", {})
            (root / "INBOX.md").write_text("# Open\n- New thought\n# Triaged\n")
            with self.assertRaisesRegex(ValueError, "INBOX changed"):
                migration.validate(root, data, True)

    def test_new_untracked_and_staged_backlogs_block_apply(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = self.make_repo(temporary)
            data = migration.inventory(root, "HEAD", {})
            (root / "NewArea").mkdir()
            (root / "NewArea/TODOs.md").write_text("# Open issues\n- New issue\n")
            for staged in (False, True):
                if staged:
                    subprocess.run(["git", "-C", str(root), "add", "."], check=True)
                with self.assertRaisesRegex(ValueError, "New backlog"):
                    migration.validate(root, data, True)

    def test_reviewed_closure_date_requires_matching_evidence(self):
        entries = sample_manifest()["entries"]
        key = "Where/TODOs.md:" + str(entries[-1]["start_line"])
        with self.assertRaisesRegex(ValueError, "evidence absent"):
            migration.apply_date_evidence(
                entries, {key: {"date": "2026-01-01", "evidence": "not in source"}}
            )
