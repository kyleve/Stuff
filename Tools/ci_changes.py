"""Select validation for PRs and main pushes, defaulting to full CI."""

import argparse
from dataclasses import dataclass
import os
from pathlib import PurePosixPath
import re
import subprocess
import sys

from Tools.ci_merge_validation import MissingMergeEvidence, validated_merge
from Tools.repository import repository_root


DOCUMENTATION_SUFFIXES = {".md", ".markdown"}
# Markdown in these directories can be rendered content or a test/build input.
# Add new Markdown consumers here before enabling their documentation shortcut.
INPUT_DIRECTORIES = {"resources", "fixtures", "__snapshots__", "src", "public"}


@dataclass(frozen=True)
class Decision:
    skip_validation: bool
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


def classify_diff(root, base, head, *, pull_request):
    scope = "PR" if pull_request else "push"
    try:
        if not all(re.fullmatch(r"[0-9a-fA-F]{40}", sha) for sha in (base, head)):
            raise ValueError("Missing commit identity")
        # PRs contribute changes since their merge base. A push contributes
        # everything that changed from the previous main tip to the new tip.
        if not pull_request:
            subprocess.run(
                ["git", "merge-base", "--is-ancestor", base, head],
                cwd=root,
                capture_output=True,
                check=True,
                timeout=10,
            )
        revisions = f"{base}...{head}" if pull_request else f"{base}..{head}"
        result = subprocess.run(
            [
                "git",
                "diff",
                "--raw",
                "-z",
                "--no-renames",
                "--no-ext-diff",
                "--no-textconv",
                revisions,
                "--",
            ],
            cwd=root,
            capture_output=True,
            check=True,
            timeout=60,
        )
        if documentation_diff(result.stdout):
            return Decision(
                True, f"The complete {scope} diff changes only documentation."
            )
        return Decision(False, f"The {scope} contains CI inputs or has an empty diff.")
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        return Decision(
            False,
            f"Cannot classify the {scope} ({type(error).__name__}). Running full CI.",
        )


def classify_changes(
    root,
    *,
    event,
    base,
    head,
    force,
    branch="",
    repository="",
    push_forced="",
    token=None,
):
    if not force and event == "push" and branch == "main" and push_forced == "false":

        def documentation_push(before):
            return classify_diff(root, before, head, pull_request=False).skip_validation

        try:
            evidence = validated_merge(
                root,
                repository,
                head,
                token,
                before=base,
                documentation_push=documentation_push,
            )
        except MissingMergeEvidence as error:
            return Decision(False, f"{error}. Running full CI.")
        except Exception as error:
            # Evidence lookup is optional. Even an unexpected provider response
            # must continue the pipeline, without exposing response data.
            return Decision(
                False,
                f"Cannot verify the merged PR ({type(error).__name__}). Running full CI.",
            )
        if evidence:
            return Decision(True, evidence)
        return Decision(False, "No matching PR validation. Running full CI.")
    if force or event != "pull_request":
        return Decision(False, "Full CI requested by this event.")
    return classify_diff(root, base, head, pull_request=True)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--event", required=True)
    parser.add_argument("--base", required=True)
    parser.add_argument("--head", required=True)
    parser.add_argument("--push-forced", default="")
    parser.add_argument("--branch", default="")
    parser.add_argument("--repository", default="")
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args(argv)
    decision = classify_changes(
        repository_root(__file__),
        event=args.event,
        base=args.base,
        head=args.head,
        force=args.force,
        branch=args.branch,
        push_forced=args.push_forced,
        repository=args.repository,
        token=os.getenv("GH_TOKEN"),
    )
    print(decision.reason, file=sys.stderr)
    print(f"skip_validation={str(decision.skip_validation).lower()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
