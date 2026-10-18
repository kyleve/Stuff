from pathlib import Path
import tempfile
import unittest

from Tools.repository import repository_root


class RepositoryTests(unittest.TestCase):
    def test_checkout_discovery_does_not_depend_on_fixture_depth(self):
        with tempfile.TemporaryDirectory(prefix="repository ü ") as temporary:
            root = Path(temporary).resolve()
            (root / ".git").mkdir()
            for depth in (0, 1, 5):
                with self.subTest(depth=depth):
                    source = root.joinpath(*(["nested"] * depth), "fixture.py")
                    source.parent.mkdir(parents=True, exist_ok=True)
                    source.touch()
                    self.assertEqual(repository_root(source), root)

    def test_linked_worktree_git_file_selects_its_own_checkout(self):
        with tempfile.TemporaryDirectory(prefix="repository ü ") as temporary:
            parent = Path(temporary).resolve()
            (parent / ".git").mkdir()
            worktree = parent / "linked checkout"
            worktree.mkdir()
            (worktree / ".git").write_text(f"gitdir: {parent}/.git/worktrees/linked\n")
            source = worktree / "tools/fixtures/fixture.py"
            source.parent.mkdir(parents=True)
            source.touch()
            self.assertEqual(repository_root(source), worktree)

    def test_symlinked_source_uses_the_source_checkout(self):
        with tempfile.TemporaryDirectory() as temporary:
            parent = Path(temporary).resolve()
            root = parent / "checkout"
            root.mkdir()
            (root / ".git").mkdir()
            source = root / "fixture.py"
            source.touch()
            link = parent / "linked-fixture.py"
            link.symlink_to(source)
            self.assertEqual(repository_root(link), root)

    def test_missing_git_marker_reports_the_source_path(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "fixture.py"
            source.touch()
            with self.assertRaisesRegex(FileNotFoundError, "Cannot find a Git checkout") as raised:
                repository_root(source)
            self.assertIn(str(source), str(raised.exception))
