"""Remove DerivedData only when Xcode's metadata proves checkout ownership."""

import argparse
from dataclasses import dataclass
import os
from pathlib import Path
import plistlib
import shutil
import stat
import sys
from typing import Optional
from xml.parsers.expat import ExpatError

from Tools.repository import repository_root


@dataclass(frozen=True)
class Cache:
    directory: Path
    workspace: Path
    device: int
    inode: int

    @property
    def checkout(self) -> Path:
        # Xcode can record the workspace embedded in an .xcodeproj bundle.
        if (
            self.workspace.name == "project.xcworkspace"
            and self.workspace.parent.suffix == ".xcodeproj"
        ):
            return self.workspace.parent.parent
        return self.workspace.parent


def read_cache(directory: Path) -> Optional[Cache]:
    """Read an ordinary directory and plist without accepting ownership links."""
    directory_stat = directory.lstat()
    if not stat.S_ISDIR(directory_stat.st_mode):
        return None
    metadata = directory / "info.plist"
    try:
        descriptor = os.open(metadata, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except FileNotFoundError:
        return None
    with os.fdopen(descriptor, "rb") as stream:
        if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
            raise ValueError("info.plist is not a regular file")
        try:
            info = plistlib.load(stream)
        except (plistlib.InvalidFileException, ExpatError) as error:
            raise ValueError(f"invalid info.plist: {error}") from error
    if not isinstance(info, dict):
        raise ValueError("info.plist is not a dictionary")
    value = info.get("WorkspacePath")
    if not isinstance(value, str) or not value or "\0" in value:
        raise ValueError("info.plist has no valid WorkspacePath")
    workspace = Path(value)
    if not workspace.is_absolute() or workspace.suffix not in (
        ".xcworkspace",
        ".xcodeproj",
    ):
        raise ValueError("WorkspacePath is not an absolute Xcode project or workspace")
    return Cache(
        directory,
        Path(os.path.normpath(workspace)),
        directory_stat.st_dev,
        directory_stat.st_ino,
    )


def is_deleted_worktree(
    cache: Cache, checkout: Path, worktree_roots: list[Path]
) -> bool:
    """Only prune absent checkouts within an available, known Codex worktree root."""
    owner = cache.checkout
    # A missing workspace or unreadable checkout does not prove removal.
    # lstat retains broken checkout symlinks and propagates permission errors.
    try:
        owner.lstat()
    except FileNotFoundError:
        pass
    else:
        return False
    # Do not infer deletion through a broken or redirected worktree ancestor.
    if any(parent.is_symlink() for parent in owner.parents):
        return False
    for root in worktree_roots:
        root = root.resolve()
        if not root.is_dir():
            continue
        try:
            relative = owner.resolve().relative_to(root)
        except ValueError:
            continue
        if len(relative.parts) == 2 and relative.parts[1] == checkout.name:
            return True
    return False


def cleanup(
    *,
    derived_data: Path,
    checkout: Path,
    worktree_roots: list[Path],
    prune: bool,
    dry_run: bool,
) -> int:
    """Plan first, then recheck ownership and directory identity before removal."""
    derived_data = derived_data.expanduser().resolve()
    checkout = checkout.resolve()
    if not derived_data.exists():
        print(f"No DerivedData directory at {derived_data}.", file=sys.stderr)
        return 0
    targets = []
    skipped = 0
    for directory in sorted(derived_data.iterdir()):
        try:
            cache = read_cache(directory)
        except (OSError, ValueError) as error:
            print(f"Skipping {directory}: {error}", file=sys.stderr)
            skipped += 1
            continue
        if cache is None:
            if directory.name.startswith(f"{checkout.name}-"):
                print(f"Skipping {directory}: no ownership metadata.", file=sys.stderr)
                skipped += 1
            continue
        eligible = (
            is_deleted_worktree(cache, checkout, worktree_roots)
            if prune
            else cache.checkout.resolve() == checkout
        )
        if eligible:
            targets.append(cache)

    removed = 0
    failures = 0
    for cache in targets:
        try:
            current = read_cache(cache.directory)
            if current != cache:
                raise ValueError("cache ownership or directory changed during cleanup")
            if prune and not is_deleted_worktree(cache, checkout, worktree_roots):
                raise ValueError("checkout reappeared or its worktree root disappeared")
            verb = "Would remove" if dry_run else "Removing"
            print(
                f"{verb} {cache.directory} (workspace: {cache.workspace})",
                file=sys.stderr,
            )
            if not dry_run:
                # rmtree does not follow child symlinks. Its descriptor-based
                # implementation also rejects replacement links on macOS/Linux.
                if not shutil.rmtree.avoids_symlink_attacks:
                    raise RuntimeError("this Python cannot safely remove cache trees")
                shutil.rmtree(cache.directory)
            removed += 1
        except (OSError, ValueError, RuntimeError) as error:
            print(f"error: cannot remove {cache.directory}: {error}", file=sys.stderr)
            failures += 1
    label = "Would remove" if dry_run else "Removed"
    print(
        f"{label} {removed} DerivedData director{'y' if removed == 1 else 'ies'}; "
        f"skipped {skipped} without usable ownership metadata; {failures} failed.",
        file=sys.stderr,
    )
    return 1 if failures else 0


def main(arguments=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument("--cleanup", action="store_true")
    modes.add_argument("--prune-derived-data", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--derived-data-root", type=Path)
    args = parser.parse_args(arguments)
    user_directory = Path.home()
    codex_directory = Path(os.environ.get("CODEX_HOME", user_directory / ".codex"))
    try:
        return cleanup(
            derived_data=args.derived_data_root
            or user_directory / "Library/Developer/Xcode/DerivedData",
            checkout=repository_root(__file__),
            worktree_roots=[
                codex_directory / "worktrees",
                user_directory / ".codex/worktrees",
                user_directory / ".codex-workspaces/worktrees",
            ],
            prune=args.prune_derived_data,
            dry_run=args.dry_run,
        )
    except (OSError, ValueError, RuntimeError) as error:
        print(f"error: DerivedData cleanup failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
