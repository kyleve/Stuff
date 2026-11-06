"""Classify the complete PR diff for both CI providers, defaulting to full CI."""

import argparse
from dataclasses import dataclass
import os
from pathlib import PurePosixPath
import re
import subprocess
import sys

from Tools.repository import repository_root


DOCUMENTATION_SUFFIXES = {".md", ".markdown"}
# Markdown in these directories can be rendered content or a test/build input.
# Add new Markdown consumers here before enabling their documentation shortcut.
INPUT_DIRECTORIES = {"resources", "fixtures", "__snapshots__", "src", "public"}


@dataclass(frozen=True)
class Decision:
    docs_only: bool
    reason: str


def documentation_path(path):
    path = PurePosixPath(path)
    return path.suffix.lower() in DOCUMENTATION_SUFFIXES and not any(
        part.lower() in INPUT_DIRECTORIES for part in path.parts[:-1]
    )


def documentation_diff(raw_diff):
    """Read NUL-delimited raw Git records with rename detection disabled."""
    if not raw_diff:
        return False
    fields = raw_diff.split(b"\0")
    if fields.pop() != b"" or len(fields) % 2:
        raise ValueError("Incomplete Git diff")
    docs_only = True
    for index in range(0, len(fields), 2):
        metadata = fields[index].split()
        if (
            len(metadata) != 5
            or not metadata[0].startswith(b":")
            or metadata[4] not in (b"A", b"M", b"D", b"T")
            or not fields[index + 1]
        ):
            raise ValueError("Unexpected Git diff record")
        # Executables, symlinks, submodules, and type changes need CI even when
        # their names end in Markdown. Deletions retain the old mode.
        modes = (metadata[0][1:], metadata[1])
        if any(mode not in (b"000000", b"100644") for mode in modes):
            docs_only = False
        if not documentation_path(os.fsdecode(fields[index + 1])):
            docs_only = False
    return docs_only


def classify_changes(root, *, event, base, head, force):
    if force or event != "pull_request":
        return Decision(False, "Full CI requested by this event.")
    try:
        if not all(re.fullmatch(r"[0-9a-fA-F]{40}", sha) for sha in (base, head)):
            raise ValueError("Missing PR commit identity")
        result = subprocess.run(
            [
                "git",
                "diff",
                "--raw",
                "-z",
                "--no-renames",
                "--no-ext-diff",
                "--no-textconv",
                f"{base}...{head}",
                "--",
            ],
            cwd=root,
            capture_output=True,
            check=True,
            timeout=60,
        )
        if documentation_diff(result.stdout):
            return Decision(True, "The complete PR diff changes only documentation.")
        return Decision(False, "The PR contains CI inputs or has an empty diff.")
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        return Decision(
            False,
            f"Cannot classify the PR ({type(error).__name__}). Running full CI.",
        )


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--event", required=True)
    parser.add_argument("--base", required=True)
    parser.add_argument("--head", required=True)
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args(argv)
    decision = classify_changes(
        repository_root(__file__),
        event=args.event,
        base=args.base,
        head=args.head,
        force=args.force,
    )
    print(decision.reason, file=sys.stderr)
    print(f"docs_only={str(decision.docs_only).lower()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
