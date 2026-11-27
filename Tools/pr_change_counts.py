"""Summarize the committed changes in a pull request as a Markdown table."""

import argparse
from dataclasses import dataclass
import os
from pathlib import PurePosixPath
import subprocess

from Tools.repository import repository_root


CATEGORIES = (
    "App code",
    "Tests",
    "Snapshots added",
    "Snapshots removed",
    "Snapshots changed",
    "Markdown",
    "Configuration",
    "Tooling",
    "Resources",
    "Other",
)
CONFIG_NAMES = {
    ".gitattributes",
    ".gitignore",
    ".swiftformat",
    ".worktreeinclude",
    ".xcode-version",
    "bumperbowling.swift",
    "ci-validation-jobs.json",
    "gemfile",
    "package-lock.json",
    "package.json",
    "package.swift",
    "project.swift",
    "tsconfig.json",
    "tuist.swift",
}
CONFIG_SUFFIXES = {
    ".cfg",
    ".entitlements",
    ".ini",
    ".lock",
    ".pbxproj",
    ".plist",
    ".resolved",
    ".toml",
    ".xcconfig",
    ".yaml",
    ".yml",
}
TOOL_DIRECTORIES = {
    ".agents",
    ".bumper",
    ".circleci",
    ".claude",
    ".codex",
    ".github",
    ".githooks",
    "fastlane",
}
RESOURCE_SUFFIXES = {
    ".geojson",
    ".gif",
    ".jpeg",
    ".jpg",
    ".pdf",
    ".png",
    ".strings",
    ".svg",
    ".twkb",
    ".webp",
    ".xcstrings",
}
SOURCE_SUFFIXES = {
    ".astro",
    ".css",
    ".html",
    ".js",
    ".jsx",
    ".mjs",
    ".swift",
    ".ts",
    ".tsx",
}


def file_category(path, original, status):
    path = PurePosixPath(os.fsdecode(path).lower())
    directories = path.parts[:-1]
    snapshot = "__snapshots__" in directories
    was_snapshot = "__snapshots__" in os.fsdecode(original).lower().split("/")[:-1]
    if snapshot or was_snapshot:
        if status == b"A" or not was_snapshot:
            return "Snapshots added"
        if status == b"D" or not snapshot:
            return "Snapshots removed"
        return "Snapshots changed"
    if path.suffix in {".md", ".markdown"}:
        return "Markdown"
    if {"tests", "snapshottests"}.intersection(directories) or any(
        marker in path.name for marker in (".test.", ".spec.")
    ):
        return "Tests"
    if (
        path.name in CONFIG_NAMES
        or path.suffix in CONFIG_SUFFIXES
        or ".config." in path.name
        or (path.suffix == ".json" and path.parts[0] in TOOL_DIRECTORIES)
    ):
        return "Configuration"
    if (
        path.suffix in RESOURCE_SUFFIXES
        or {"resources", "public"}.intersection(directories)
        or any(directory.endswith(".xcassets") for directory in directories)
    ):
        return "Resources"
    if (
        path.parts[:4] == ("tools", "installerkit", "site", "src")
        and path.suffix in SOURCE_SUFFIXES
    ):
        return "App code"
    if (
        path.parts[0] in TOOL_DIRECTORIES
        or {"tools", "prototypes"}.intersection(directories)
        or (not directories and not path.suffix and path.name != "license")
    ):
        return "Tooling"
    if path.suffix in SOURCE_SUFFIXES:
        return "App code"
    return "Other"


@dataclass
class Counts:
    files: int = 0
    added: int = 0
    deleted: int = 0
    binary: int = 0

    def add(self, added, deleted):
        self.files += 1
        if added == deleted == b"-":
            self.binary += 1
        else:
            self.added += int(added)
            self.deleted += int(deleted)

    def row(self, category):
        return f"| {category} | {self.files:,} | {self.added:,} | {self.deleted:,} | {self.binary:,} |"


def markdown_table(diff):
    counts = {category: Counts() for category in CATEGORIES}
    total = Counts()
    fields = diff.split(b"\0")
    if fields.pop():
        raise ValueError("Incomplete Git diff")
    records = iter(fields)
    paths = {}
    # Git emits all raw status records first, followed by the numstat records.
    for record in records:
        if record.startswith(b":"):
            status = record.split()[-1][:1]
            original = next(records)
            destination = next(records) if status in (b"C", b"R") else original
            paths[destination] = (status, original)
            continue
        added, deleted, destination = record.split(b"\t", 2)
        if not destination:
            next(records)  # Original path, already read from the raw record.
            destination = next(records)
        status, original = paths.pop(destination)
        category = file_category(destination, original, status)
        # PNG snapshots can be Git LFS pointers even when the current checkout
        # lacks the attributes that tell Git to treat them as binary.
        if category.startswith("Snapshots ") and (
            destination.lower().endswith(b".png") or original.lower().endswith(b".png")
        ):
            added = deleted = b"-"
        counts[category].add(added, deleted)
        total.add(added, deleted)
    if paths:
        raise ValueError("Incomplete Git diff")

    rows = [
        "| Category | Files | Lines added | Lines deleted | Binary files |",
        "| --- | ---: | ---: | ---: | ---: |",
    ]
    ordered_counts = sorted(
        counts.items(),
        key=lambda item: (item[1].added + item[1].deleted, item[1].files),
        reverse=True,
    )
    rows.extend(
        count.row(category) for category, count in ordered_counts if count.files
    )
    rows.append(total.row("**Total**"))
    return "\n".join(rows)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--base", default="origin/main", help="PR base ref (default: origin/main)"
    )
    parser.add_argument("--head", default="HEAD", help="PR head ref (default: HEAD)")
    args = parser.parse_args(argv)

    try:
        root = repository_root(__file__)
        revisions = []
        for ref in (args.base, args.head):
            resolved = subprocess.run(
                [
                    "git",
                    "rev-parse",
                    "--verify",
                    "--end-of-options",
                    f"{ref}^{{commit}}",
                ],
                cwd=root,
                capture_output=True,
                check=False,
            )
            if resolved.returncode:
                parser.exit(
                    resolved.returncode, f"error: cannot resolve Git ref {ref!r}\n"
                )
            revisions.append(resolved.stdout.decode("ascii").strip())

        diff = subprocess.run(
            [
                "git",
                "-c",
                "diff.lfs.binary=true",
                "diff",
                "--raw",
                "--numstat",
                "-z",
                "--find-renames",
                "--no-textconv",
                "--no-ext-diff",
                "--ignore-submodules=none",
                "...".join(revisions),
                "--",
            ],
            cwd=root,
            stdout=subprocess.PIPE,
            check=False,
        )
        if diff.returncode:
            return diff.returncode
        print(markdown_table(diff.stdout))
    except OSError as error:
        parser.exit(1, f"error: {error}\n")
    except (ValueError, KeyError, StopIteration):
        parser.exit(1, "error: cannot read Git diff statistics\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
