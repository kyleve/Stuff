import contextlib
import io
import os
from pathlib import Path
import plistlib
import shutil
import tempfile
import unittest
from unittest import mock

from Tools import worktree_cleanup


class WorktreeCleanupTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="worktree cleanup ü ")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.checkout = self.root / "Stuff"
        self.derived_data = self.root / "DerivedData"
        self.worktree_roots = [
            self.root / ".codex/worktrees",
            self.root / ".codex-workspaces/worktrees",
        ]
        for directory in [self.checkout, self.derived_data, *self.worktree_roots]:
            directory.mkdir(parents=True)

    def cache(self, name, checkout=None, workspace=None):
        directory = self.derived_data / name
        directory.mkdir()
        if workspace is None:
            workspace = (checkout or self.checkout) / "Stuff.xcworkspace"
        with (directory / "info.plist").open("wb") as stream:
            plistlib.dump(
                {"WorkspacePath": str(workspace)}, stream, fmt=plistlib.FMT_BINARY
            )
        (directory / "build-product").write_text("compiled data")
        return directory

    def run_cleanup(self, *, prune=False, dry_run=False):
        stdout, stderr = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            status = worktree_cleanup.cleanup(
                derived_data=self.derived_data,
                checkout=self.checkout,
                worktree_roots=self.worktree_roots,
                prune=prune,
                dry_run=dry_run,
            )
        self.assertEqual(stdout.getvalue(), "")
        return status, stderr.getvalue()

    def test_cleanup_uses_exact_checkout_not_cache_name_or_path_prefix(self):
        owned = self.cache("arbitrary-cache-name")
        others = [
            self.cache("Stuff-other", checkout=self.root / "other/Stuff"),
            self.cache("Stuff-prefix", checkout=self.root / "Stuff-backup"),
            self.cache("Stuff-nested", checkout=self.checkout / "nested/Stuff"),
        ]
        status, output = self.run_cleanup()
        self.assertEqual(status, 0, output)
        self.assertFalse(owned.exists())
        self.assertTrue(all(path.exists() for path in others))
        self.assertIn("Removed 1 DerivedData directory", output)

    def test_project_and_embedded_workspace_are_owned_by_the_checkout(self):
        project = self.cache("project", workspace=self.checkout / "Stuff.xcodeproj")
        embedded = self.cache(
            "embedded", workspace=self.checkout / "Stuff.xcodeproj/project.xcworkspace"
        )
        status, output = self.run_cleanup()
        self.assertEqual(status, 0, output)
        self.assertFalse(project.exists())
        self.assertFalse(embedded.exists())

    def test_cleanup_resolves_checkout_aliases(self):
        alias = self.root / "alias"
        alias.symlink_to(self.checkout, target_is_directory=True)
        owned = self.cache("alias-cache", checkout=alias)
        status, output = self.run_cleanup()
        self.assertEqual(status, 0, output)
        self.assertFalse(owned.exists())

    def test_dry_run_preserves_every_file_and_reports_exact_target(self):
        owned = self.cache("owned")
        before = {path: path.read_bytes() for path in owned.iterdir()}
        status, output = self.run_cleanup(dry_run=True)
        self.assertEqual(status, 0, output)
        self.assertIn(f"Would remove {owned}", output)
        self.assertEqual(before, {path: path.read_bytes() for path in owned.iterdir()})

    def test_prune_handles_deleted_parent_directories_in_current_and_legacy_roots(self):
        orphaned = [
            self.cache(f"orphan-{index}", checkout=root / "deleted/Stuff")
            for index, root in enumerate(self.worktree_roots)
        ]
        live_checkout = self.worktree_roots[0] / "live/Stuff"
        live_checkout.mkdir(parents=True)
        retained = [
            self.cache("live-without-workspace", checkout=live_checkout),
            self.cache("primary"),
            self.cache("other-repo", checkout=self.worktree_roots[0] / "old/Other"),
            self.cache("unmanaged", checkout=self.root / "deleted/Stuff"),
            self.cache(
                "near-root", checkout=self.root / ".codex/worktrees-old/id/Stuff"
            ),
        ]
        status, output = self.run_cleanup(prune=True, dry_run=True)
        self.assertEqual(status, 0, output)
        self.assertTrue(all(path.exists() for path in orphaned))
        status, output = self.run_cleanup(prune=True)
        self.assertEqual(status, 0, output)
        self.assertTrue(all(not path.exists() for path in orphaned))
        self.assertTrue(all(path.exists() for path in retained))

    def test_prune_preserves_caches_when_worktree_root_is_unavailable(self):
        owned = self.cache("orphan", checkout=self.worktree_roots[0] / "old/Stuff")
        self.worktree_roots[0].rmdir()
        status, output = self.run_cleanup(prune=True)
        self.assertEqual(status, 0, output)
        self.assertTrue(owned.exists())

    def test_unreadable_checkout_fails_cli_without_removing_any_planned_cache(self):
        orphan = self.cache("a-orphan", checkout=self.worktree_roots[0] / "gone/Stuff")
        owner = self.worktree_roots[0] / "restricted/Stuff"
        owner.mkdir(parents=True)
        retained = self.cache("z-restricted", checkout=owner)
        original_stat = Path.lstat

        def deny_checkout_stat(path):
            if path == owner:
                raise PermissionError(f"cannot inspect {path}")
            return original_stat(path)

        with (
            mock.patch.object(Path, "lstat", deny_checkout_stat),
            mock.patch.object(Path, "home", return_value=self.root),
            mock.patch.object(
                worktree_cleanup, "repository_root", return_value=self.checkout
            ),
            contextlib.redirect_stderr(io.StringIO()) as stderr,
        ):
            status = worktree_cleanup.main(
                ["--prune-derived-data", "--derived-data-root", str(self.derived_data)]
            )
        self.assertEqual(status, 1, stderr.getvalue())
        self.assertIn("cannot inspect", stderr.getvalue())
        self.assertTrue(retained.exists())
        self.assertTrue(orphan.exists())

    def test_prune_preserves_broken_checkout_and_ancestor_symlinks(self):
        container = self.worktree_roots[0] / "old"
        container.mkdir()
        (container / "Stuff").symlink_to(self.worktree_roots[0] / "gone/Stuff")
        linked_parent = self.worktree_roots[0] / "alias"
        linked_parent.symlink_to(self.worktree_roots[0] / "absent")
        retained = [
            self.cache("broken-checkout", checkout=container / "Stuff"),
            self.cache("broken-parent", checkout=linked_parent / "Stuff"),
        ]
        status, output = self.run_cleanup(prune=True)
        self.assertEqual(status, 0, output)
        self.assertTrue(all(path.exists() for path in retained))

    def test_missing_metadata_and_shared_caches_are_retained(self):
        for name in ("Stuff-no-info", "ModuleCache.noindex"):
            (self.derived_data / name).mkdir()
        status, output = self.run_cleanup()
        self.assertEqual(status, 0, output)
        self.assertIn("Stuff-no-info: no ownership metadata", output)
        self.assertNotIn("ModuleCache.noindex", output)
        self.assertEqual(len(list(self.derived_data.iterdir())), 2)

    def test_invalid_plists_and_workspace_paths_are_reported_and_retained(self):
        payloads = [
            b"corrupt plist",
            b'<?xml version="1.0"?><plist><dict>',
            plistlib.dumps([]),
            plistlib.dumps({}),
            plistlib.dumps({"WorkspacePath": 42}),
            plistlib.dumps({"WorkspacePath": "Stuff.xcworkspace"}),
            plistlib.dumps({"WorkspacePath": str(self.checkout / "unrelated")}),
        ]
        for index, payload in enumerate(payloads):
            cache = self.cache(f"invalid-{index}")
            (cache / "info.plist").write_bytes(payload)
        status, output = self.run_cleanup()
        self.assertEqual(status, 0, output)
        self.assertEqual(output.count("Skipping"), len(payloads))
        self.assertEqual(len(list(self.derived_data.iterdir())), len(payloads))

    def test_linked_cache_and_metadata_never_authorize_deletion(self):
        external = self.root / "external"
        external.mkdir()
        (self.derived_data / "Stuff-link").symlink_to(
            external, target_is_directory=True
        )
        linked_metadata = self.cache("linked-metadata")
        metadata = linked_metadata / "info.plist"
        metadata.rename(external / "info.plist")
        metadata.symlink_to(external / "info.plist")
        status, output = self.run_cleanup()
        self.assertEqual(status, 0, output)
        self.assertTrue((external / "info.plist").exists())
        self.assertTrue(linked_metadata.exists())
        self.assertIn("Skipping", output)

    def test_non_regular_metadata_is_rejected_without_waiting_for_a_writer(self):
        cache = self.cache("fifo")
        (cache / "info.plist").unlink()
        os.mkfifo(cache / "info.plist")
        status, output = self.run_cleanup()
        self.assertEqual(status, 0, output)
        self.assertTrue(cache.exists())
        self.assertIn("not a regular file", output)

    def test_removal_does_not_follow_child_symlinks(self):
        owned = self.cache("owned")
        external = self.root / "keep-me"
        external.mkdir()
        (external / "data").write_text("keep")
        (owned / "link").symlink_to(external, target_is_directory=True)
        status, output = self.run_cleanup()
        self.assertEqual(status, 0, output)
        self.assertFalse(owned.exists())
        self.assertEqual((external / "data").read_text(), "keep")

    def test_replaced_directory_is_retained_and_cleanup_fails(self):
        owned = self.cache("owned")
        original_read = worktree_cleanup.read_cache
        reads = 0

        def replace_before_recheck(directory):
            nonlocal reads
            reads += 1
            if reads == 2:
                owned.rename(self.root / "original-cache")
                self.cache("owned")
            return original_read(directory)

        with mock.patch.object(worktree_cleanup, "read_cache", replace_before_recheck):
            status, output = self.run_cleanup()
        self.assertEqual(status, 1, output)
        self.assertTrue(owned.exists())
        self.assertTrue((self.root / "original-cache").exists())
        self.assertIn("directory changed", output)

    def test_changed_metadata_is_retained_and_cleanup_fails(self):
        owned = self.cache("owned")
        original_read = worktree_cleanup.read_cache
        reads = 0

        def change_before_recheck(directory):
            nonlocal reads
            reads += 1
            if reads == 2:
                (owned / "info.plist").write_bytes(
                    plistlib.dumps(
                        {"WorkspacePath": str(self.root / "Other.xcworkspace")}
                    )
                )
            return original_read(directory)

        with mock.patch.object(worktree_cleanup, "read_cache", change_before_recheck):
            status, output = self.run_cleanup()
        self.assertEqual(status, 1, output)
        self.assertTrue(owned.exists())
        self.assertIn("ownership or directory changed", output)

    def test_restored_checkout_prevents_planned_prune(self):
        owner = self.worktree_roots[0] / "old/Stuff"
        owned = self.cache("orphan", checkout=owner)
        original_predicate = worktree_cleanup.is_deleted_worktree

        def restore_after_plan(*arguments):
            result = original_predicate(*arguments)
            owner.mkdir(parents=True, exist_ok=True)
            return result

        with mock.patch.object(
            worktree_cleanup, "is_deleted_worktree", restore_after_plan
        ):
            status, output = self.run_cleanup(prune=True)
        self.assertEqual(status, 1, output)
        self.assertTrue(owned.exists())
        self.assertIn("checkout reappeared", output)

    def test_removal_failure_is_visible_and_other_targets_still_run(self):
        first = self.cache("a-cache")
        second = self.cache("b-cache")
        original_remove = shutil.rmtree

        def fail_first(path):
            if path == first:
                raise PermissionError("injected removal failure")
            original_remove(path)

        fail_first.avoids_symlink_attacks = True
        with mock.patch.object(worktree_cleanup.shutil, "rmtree", fail_first):
            status, output = self.run_cleanup()
        self.assertEqual(status, 1, output)
        self.assertTrue(first.exists())
        self.assertFalse(second.exists())
        self.assertIn("injected removal failure", output)
        self.assertIn("1 failed", output)

    def test_missing_derived_data_is_an_idempotent_noop(self):
        self.derived_data.rmdir()
        status, output = self.run_cleanup()
        self.assertEqual(status, 0, output)
        self.assertFalse(self.derived_data.exists())
        self.assertIn("No DerivedData directory", output)

    def test_cli_uses_default_locations_without_creating_missing_directories(self):
        with (
            mock.patch.object(Path, "home", return_value=self.root),
            mock.patch.object(
                worktree_cleanup, "repository_root", return_value=self.checkout
            ),
            contextlib.redirect_stderr(io.StringIO()) as stderr,
        ):
            status = worktree_cleanup.main(["--prune-derived-data", "--dry-run"])
        self.assertEqual(status, 0, stderr.getvalue())
        self.assertFalse((self.root / "Library").exists())

    def test_cli_cleanup_removes_owned_cache_from_default_xcode_location(self):
        self.cache("owned")
        default_location = self.root / "Library/Developer/Xcode/DerivedData"
        default_location.parent.mkdir(parents=True)
        self.derived_data.rename(default_location)
        with (
            mock.patch.object(Path, "home", return_value=self.root),
            mock.patch.object(
                worktree_cleanup, "repository_root", return_value=self.checkout
            ),
            contextlib.redirect_stderr(io.StringIO()) as stderr,
        ):
            status = worktree_cleanup.main(["--cleanup"])
        self.assertEqual(status, 0, stderr.getvalue())
        self.assertIn("Removed 1 DerivedData directory", stderr.getvalue())
        self.assertEqual(list(default_location.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
