"""Locate the checkout that owns a tool without assuming its directory depth."""

from pathlib import Path


def repository_root(source_file):
    """Find the nearest checkout, including a linked worktree's .git file."""
    for directory in Path(source_file).resolve().parents:
        marker = directory / ".git"
        if marker.is_dir() or marker.is_file():
            return directory
    raise FileNotFoundError(f"Cannot find a Git checkout containing {source_file}")
