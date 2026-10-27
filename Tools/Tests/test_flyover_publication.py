"""Publication failures use temporary directories and the actual rename boundary."""

import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from Tools.flyover_publication import (
    AtlasPublication,
    resolve_destination,
    validate_destination,
)
from Tools.flyover_cli import Interrupted


class FlyoverPublicationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.destination = self.root / "atlas"
        self.destination.mkdir()
        (self.destination / ".flyover-generated").write_text("schemaVersion=1\n")
        (self.destination / "old").write_text("previous")

    def test_publish_replaces_and_normalizes_modes(self):
        with AtlasPublication(self.destination) as publication:
            (publication.staging / "new").write_text("next")
            publication.publish()
        self.assertFalse((self.destination / "old").exists())
        self.assertEqual((self.destination / "new").read_text(), "next")
        self.assertEqual((self.destination / "new").stat().st_mode & 0o777, 0o644)
        self.assertEqual(self.destination.stat().st_mode & 0o777, 0o755)
        self.assertEqual(list(self.root.iterdir()), [self.destination])

    def test_failed_install_restores_previous_directory(self):
        rename = os.rename

        def fail_install(source, target):
            if Path(source).name.startswith(".flyover-staging."):
                raise OSError("install failed")
            return rename(source, target)

        with self.assertRaisesRegex(OSError, "install failed"):
            with patch("Tools.flyover_publication.os.rename", side_effect=fail_install):
                with AtlasPublication(self.destination) as publication:
                    publication.publish()
        self.assertEqual((self.destination / "old").read_text(), "previous")
        self.assertEqual(list(self.root.iterdir()), [self.destination])

    def test_failed_backup_move_preserves_destination_and_cleans_staging(self):
        with self.assertRaisesRegex(OSError, "backup move failed"):
            with patch(
                "Tools.flyover_publication.os.rename",
                side_effect=OSError("backup move failed"),
            ):
                with AtlasPublication(self.destination) as publication:
                    publication.publish()
        self.assertEqual((self.destination / "old").read_text(), "previous")
        self.assertEqual(list(self.root.iterdir()), [self.destination])

    def test_staging_cleanup_failure_preserves_original_error_and_staging(self):
        with self.assertRaisesRegex(OSError, "capture failed; staging cleanup failed"):
            with patch(
                "Tools.flyover_publication.shutil.rmtree",
                side_effect=OSError("permission denied"),
            ):
                with AtlasPublication(self.destination) as publication:
                    raise ValueError("capture failed")
        self.assertTrue(publication.staging.exists())
        self.assertEqual((self.destination / "old").read_text(), "previous")

    def test_failed_rollback_retains_backup_and_reports_both_errors(self):
        rename = os.rename

        def fail_install_and_restore(source, target):
            if Path(target) == self.destination:
                raise OSError("rename failed")
            return rename(source, target)

        with self.assertRaisesRegex(
            OSError, "rename failed; backup recovery or cleanup failed"
        ):
            with patch(
                "Tools.flyover_publication.os.rename",
                side_effect=fail_install_and_restore,
            ):
                with AtlasPublication(self.destination) as publication:
                    publication.publish()
        self.assertEqual(
            (publication.backup_container / "previous/old").read_text(), "previous"
        )

    def test_pending_signal_does_not_hide_recovery_failure(self):
        with self.assertRaisesRegex(OSError, "capture failed; staging cleanup failed"):
            with (
                patch(
                    "Tools.flyover_publication.signal.pthread_sigmask",
                    side_effect=[set(), Interrupted(signal.SIGTERM)],
                ),
                patch(
                    "Tools.flyover_publication.shutil.rmtree",
                    side_effect=OSError("permission denied"),
                ),
            ):
                with AtlasPublication(self.destination):
                    raise ValueError("capture failed")
        self.assertEqual((self.destination / "old").read_text(), "previous")

    def test_cleanup_failure_after_commit_keeps_new_atlas(self):
        with self.assertRaisesRegex(OSError, "cleanup failed"):
            with patch(
                "Tools.flyover_publication.shutil.rmtree",
                side_effect=OSError("cleanup failed"),
            ):
                with AtlasPublication(self.destination) as publication:
                    (publication.staging / "new").write_text("next")
                    publication.publish()
        self.assertEqual((self.destination / "new").read_text(), "next")
        self.assertEqual(
            (publication.backup_container / "previous/old").read_text(), "previous"
        )

    def test_competing_destination_is_not_overwritten_during_recovery(self):
        rename = os.rename

        def compete(source, target):
            if Path(source).name.startswith(".flyover-staging."):
                self.destination.mkdir()
                (self.destination / "competitor").write_text("retained")
                raise OSError("destination appeared")
            return rename(source, target)

        with self.assertRaisesRegex(OSError, "recovery material retained"):
            with patch("Tools.flyover_publication.os.rename", side_effect=compete):
                with AtlasPublication(self.destination) as publication:
                    publication.publish()
        self.assertTrue((self.destination / "competitor").exists())
        self.assertTrue((publication.backup_container / "previous/old").exists())

    def test_interruption_after_install_keeps_new_atlas_without_rollback(self):
        rename = os.rename

        def interrupt_after_install(source, target):
            rename(source, target)
            if Path(source).name.startswith(".flyover-staging."):
                raise Interrupted(signal.SIGTERM)

        with self.assertRaises(Interrupted):
            with patch(
                "Tools.flyover_publication.os.rename",
                side_effect=interrupt_after_install,
            ):
                with AtlasPublication(self.destination) as publication:
                    (publication.staging / "new").write_text("next")
                    publication.publish()
        self.assertEqual((self.destination / "new").read_text(), "next")
        self.assertEqual(list(self.root.iterdir()), [self.destination])

    def test_competing_destination_after_install_retains_backup(self):
        with self.assertRaisesRegex(OSError, "recovery material retained"):
            with AtlasPublication(self.destination) as publication:
                publication.publish()
                self.destination.rename(self.root / "moved-new-atlas")
                self.destination.mkdir()
                (self.destination / "competitor").write_text("retained")
        self.assertTrue((self.destination / "competitor").exists())
        self.assertTrue((publication.backup_container / "previous/old").exists())

    def test_revalidates_marker_before_publication(self):
        with self.assertRaisesRegex(ValueError, "unmarked"):
            with AtlasPublication(self.destination) as publication:
                (self.destination / ".flyover-generated").unlink()
                publication.publish()
        self.assertTrue((self.destination / "old").exists())

    def test_protected_aliases_and_replacement_links(self):
        alias = self.root / "alias"
        alias.symlink_to("/")
        with self.assertRaisesRegex(ValueError, "filesystem root"):
            resolve_destination(str(alias), self.root, action="replace")
        alias.unlink()
        alias.symlink_to(self.destination)
        with self.assertRaisesRegex(ValueError, "non-directory"):
            validate_destination(alias)

    def test_signals_between_renames_restore_old_atlas(self):
        for number in (signal.SIGINT, signal.SIGTERM):
            with self.subTest(number=number):
                result = subprocess.run(
                    [
                        sys.executable,
                        "-B",
                        "-c",
                        """
import os, signal, sys
from pathlib import Path
from unittest.mock import patch
from Tools.flyover_cli import interruption_handling, Interrupted
from Tools.flyover_publication import AtlasPublication
destination = Path(sys.argv[1])
rename = os.rename
def interrupt(source, target):
    rename(source, target)
    if Path(source) == destination:
        os.kill(os.getpid(), int(sys.argv[2]))
try:
    with interruption_handling(), patch('Tools.flyover_publication.os.rename', side_effect=interrupt):
        with AtlasPublication(destination) as publication:
            publication.publish()
except Interrupted as error:
    sys.exit(128 + error.number)
""",
                        str(self.destination),
                        str(int(number)),
                    ],
                    capture_output=True,
                    text=True,
                    timeout=10,
                )
                self.assertEqual(result.returncode, 128 + number, result.stderr)
                self.assertEqual((self.destination / "old").read_text(), "previous")
                self.assertEqual(list(self.root.iterdir()), [self.destination])

    def test_first_signal_during_recovery_does_not_skip_backup_restore(self):
        for number in (signal.SIGINT, signal.SIGTERM):
            with self.subTest(number=number):
                result = subprocess.run(
                    [
                        sys.executable,
                        "-B",
                        "-c",
                        """
import os, shutil, signal, sys
from pathlib import Path
from unittest.mock import patch
from Tools.flyover_cli import interruption_handling, Interrupted
from Tools.flyover_publication import AtlasPublication
destination = Path(sys.argv[1])
rename, rmtree = os.rename, shutil.rmtree
def fail_install(source, target):
    if Path(source).name.startswith('.flyover-staging.'):
        raise OSError('install failed')
    return rename(source, target)
def interrupt_cleanup(path):
    os.kill(os.getpid(), int(sys.argv[2]))
    return rmtree(path)
try:
    with interruption_handling():
        with patch('Tools.flyover_publication.os.rename', side_effect=fail_install), \
             patch('Tools.flyover_publication.shutil.rmtree', side_effect=interrupt_cleanup):
            with AtlasPublication(destination) as publication:
                publication.publish()
except Interrupted as error:
    sys.exit(128 + error.number)
""",
                        str(self.destination),
                        str(int(number)),
                    ],
                    capture_output=True,
                    text=True,
                    timeout=10,
                )
                self.assertEqual(result.returncode, 128 + number, result.stderr)
                self.assertEqual((self.destination / "old").read_text(), "previous")
                self.assertEqual(list(self.root.iterdir()), [self.destination])
