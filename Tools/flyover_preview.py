"""Command-line validation for generated Flyover atlases."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

try:
    from Tools.flyover_manifest import (
        FlyoverArtifactError,
        validate_artifact,
    )
except ModuleNotFoundError as error:
    if error.name != "Tools":
        raise
    from flyover_manifest import (
        FlyoverArtifactError,
        validate_artifact,
    )


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
