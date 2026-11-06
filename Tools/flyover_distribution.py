"""Validate and publish a Flyover archive supplied by the native workflow."""

import argparse
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

from Tools.flyover_bundle import unpack_bundle


def publish(archive: Path, repository: str, sha: str, run: str, attempt: str) -> None:
    if not re.fullmatch(r"[0-9a-f]{40}", sha):
        raise ValueError("An exact capture commit is required")
    if not all(re.fullmatch(r"[1-9][0-9]*", value) for value in (run, attempt)):
        raise ValueError("Invalid publication identity")
    with tempfile.TemporaryDirectory(prefix="flyover-publish-") as temporary:
        extracted = Path(temporary)
        unpack_bundle(archive, extracted, sha)
        # Immutable, non-latest releases retain the previous successful artifact.
        # Draft creation prevents an incomplete upload from becoming selectable.
        tag = f"flyover-atlas-{run}-{attempt}"
        subprocess.run(
            [
                "gh",
                "release",
                "create",
                tag,
                str(archive),
                "--repo",
                repository,
                "--target",
                sha,
                "--draft",
                "--prerelease",
                "--latest=false",
                "--title",
                f"Flyover atlas {run}.{attempt}",
                "--notes",
                f"Native QA captures from {sha}.",
            ],
            check=True,
        )
        subprocess.run(
            ["gh", "release", "edit", tag, "--repo", repository, "--draft=false"],
            check=True,
        )


def main(arguments=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", required=True, type=Path)
    parser.add_argument("--sha", required=True)
    parser.add_argument("--run", required=True)
    parser.add_argument("--attempt", required=True)
    args = parser.parse_args(arguments)
    try:
        publish(
            args.archive,
            os.environ["GITHUB_REPOSITORY"],
            args.sha,
            args.run,
            args.attempt,
        )
    except Exception as error:
        print(f"Flyover publication failed ({type(error).__name__}).", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
