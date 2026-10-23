"""Validate and securely open Flyover artifacts before an Astro preview copies them."""

from __future__ import annotations

import argparse
import os
import stat
import sys
from contextlib import contextmanager
from pathlib import Path, PurePosixPath
from typing import BinaryIO, Iterator, Optional

try:
    from Tools.flyover_manifest import (
        FlyoverArtifact,
        FlyoverArtifactError,
        validate_artifact,
    )
except ModuleNotFoundError as error:
    if error.name != "Tools":
        raise
    from flyover_manifest import (
        FlyoverArtifact,
        FlyoverArtifactError,
        validate_artifact,
    )


def _open_file_beneath(root_descriptor: int, relative: str) -> BinaryIO:
    """Open one allowlisted regular file without following symbolic links."""
    flags = os.O_RDONLY | os.O_NOFOLLOW
    directory_flags = flags | os.O_DIRECTORY
    current_descriptor = os.dup(root_descriptor)
    file_descriptor: Optional[int] = None
    try:
        parts = PurePosixPath(relative).parts
        for part in parts[:-1]:
            next_descriptor = os.open(
                part,
                directory_flags,
                dir_fd=current_descriptor,
            )
            os.close(current_descriptor)
            current_descriptor = next_descriptor
        # A file can become a FIFO after startup validation. Do not wait for a
        # writer before fstat can reject it. O_NONBLOCK does not affect regular files.
        file_descriptor = os.open(
            parts[-1], flags | os.O_NONBLOCK, dir_fd=current_descriptor
        )
        if not stat.S_ISREG(os.fstat(file_descriptor).st_mode):
            raise OSError("the request target is not a regular file")
        file = os.fdopen(file_descriptor, "rb")
        file_descriptor = None
        return file
    finally:
        if file_descriptor is not None:
            os.close(file_descriptor)
        os.close(current_descriptor)


@contextmanager
def _open_artifact_root(artifact: FlyoverArtifact) -> Iterator[int]:
    """Pin the validated atlas directory while copying its allowlisted files."""
    try:
        descriptor = os.open(
            artifact.root,
            os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
        )
    except OSError as error:
        raise FlyoverArtifactError(
            f"could not open the validated atlas directory {artifact.root}: {error}"
        ) from error
    try:
        status = os.fstat(descriptor)
        if (status.st_dev, status.st_ino) != (artifact.root_device, artifact.root_inode):
            raise FlyoverArtifactError("the atlas directory changed during server startup")
        yield descriptor
    finally:
        os.close(descriptor)


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(add_help=False)
    subparsers = parser.add_subparsers(dest="command", required=True)

    validate = subparsers.add_parser("validate", add_help=False)
    validate.add_argument("directory", type=Path)
    validate.add_argument("--without-marker", action="store_true")

    return parser


def main(arguments: list[str] | None = None) -> int:
    try:
        options = _parser().parse_args(arguments)
        if options.command == "validate":
            validate_artifact(
                options.directory,
                require_marker=not options.without_marker,
            )
        return 0
    except FlyoverArtifactError as error:
        print(f"flyover: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
