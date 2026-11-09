#!/usr/bin/env python3
"""Inventory, apply, and verify the one-time Stuff backlog migration."""

import argparse
from collections import Counter
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

from backlog_inventory import (
    TEAM_ID,
    WORKSPACE,
    digest,
    parse_file,
    estimate_creation_dates,
)
from datetime import date
from backlog_linear import Linear, LinearError, apply, verify
from repository import repository_root

ROOT = repository_root(__file__)
DEFAULT_MANIFEST = ROOT / "Tools/BacklogMigration/manifest.json"


def git(root, *args):
    return subprocess.check_output(["git", *args], cwd=root, text=True)


def source_files(root, revision):
    return sorted(
        path
        for path in git(root, "ls-tree", "-r", "--name-only", revision).splitlines()
        if Path(path).name == "TODOs.md"
    )


def apply_date_evidence(entries, overrides):
    known = {f"{entry['path']}:{entry['start_line']}": entry for entry in entries}
    for key, values in overrides.items():
        entry = known[key]
        if entry["state"] != "Done":
            raise ValueError(f"Completion override targets an open issue: {key}")
        if values["evidence"] not in entry["body"] + entry["context"]:
            parent = next(
                (item for item in entries if item["id"] == entry["parent_id"]), None
            )
            if parent is None or values["evidence"] not in parent["body"]:
                raise ValueError(f"Completion evidence absent: {key}")
            entry["context"] += "\n\nParent completion evidence: " + values["evidence"]
        date.fromisoformat(values["date"])
        entry["dates"]["completedAt"] = values["date"] + "T00:00:00Z"


def inventory(root, revision, split_nested, date_evidence=None):
    revision = git(root, "rev-parse", revision).strip()
    files = []
    entries = []
    for path in source_files(root, revision):
        source = git(root, "show", f"{revision}:{path}")
        splits = split_nested.get(path, [])
        entries.extend(parse_file(path, source, revision, splits))
        files.append(
            {
                "path": path,
                "sha256": digest(source),
                "line_count": len(source.splitlines()),
                "split_nested_lines": splits,
            }
        )
    apply_date_evidence(entries, date_evidence or {})
    estimate_creation_dates(entries)
    if not entries:
        raise ValueError("No backlog entries found.")
    inbox = git(root, "show", f"{revision}:INBOX.md")
    if any(
        line.startswith("- ")
        for line in inbox.split("# Open\n", 1)[-1].split("# Triaged", 1)[0].splitlines()
    ):
        raise ValueError(
            "INBOX has new entries. Add an explicit intake mapping before migration."
        )
    return {
        "version": 1,
        "workspace": WORKSPACE,
        "team_id": TEAM_ID,
        "source_revision": revision,
        "date_evidence": date_evidence or {},
        "files": files,
        "inbox_sha256": digest(inbox),
        "entries": entries,
    }


def validate(root, manifest, require_sources):
    if (
        manifest["version"] != 1
        or manifest["team_id"] != TEAM_ID
        or manifest["workspace"] != WORKSPACE
    ):
        raise ValueError("Unsupported manifest or destination.")
    revision = manifest["source_revision"]
    if source_files(root, revision) != sorted(
        item["path"] for item in manifest["files"]
    ):
        raise ValueError("Manifest does not cover the source revision's backlog files.")
    expected = []
    for item in manifest["files"]:
        source = git(root, "show", f"{revision}:{item['path']}")
        if digest(source) != item["sha256"]:
            raise ValueError("Source revision hash differs.")
        live = root / item["path"]
        if live.exists():
            if digest(live.read_text()) != item["sha256"]:
                raise ValueError(f"Source changed after inventory: {item['path']}")
        elif require_sources:
            raise ValueError(f"Source missing before apply: {item['path']}")
        expected.extend(
            parse_file(item["path"], source, revision, item["split_nested_lines"])
        )
    apply_date_evidence(expected, manifest.get("date_evidence", {}))
    estimate_creation_dates(expected)
    actual = manifest["entries"]
    if len(actual) != len(expected) or len({entry["id"] for entry in actual}) != len(
        actual
    ):
        raise ValueError("Missing or duplicated manifest entries.")
    for original, entry in zip(expected, actual):
        for key, value in original.items():
            if key not in ("identifier", "url") and entry[key] != value:
                raise ValueError(
                    f"Manifest differs from source inventory: {original['source_key']} {key}"
                )
    inbox = root / "INBOX.md"
    if inbox.exists() and digest(inbox.read_text()) != manifest["inbox_sha256"]:
        raise ValueError("INBOX changed after inventory.")
    if require_sources and not inbox.exists():
        raise ValueError("INBOX missing before apply.")
    # Detect new backlog files at the current revision, not just changed known files.
    live_paths = {
        path
        for path in git(
            root, "ls-files", "--cached", "--others", "--exclude-standard", "-z"
        ).split("\0")
        if Path(path).name == "TODOs.md"
    }
    if live_paths - {item["path"] for item in manifest["files"]}:
        raise ValueError("New backlog files appeared after inventory.")


def save_manifest(path, manifest):
    path.parent.mkdir(parents=True, exist_ok=True)
    # A single-file checkpoint: readers observe either the old or complete new JSON.
    fd, temporary = tempfile.mkstemp(prefix=path.name + ".", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(manifest, stream, indent=2, ensure_ascii=False)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("inventory", "apply", "verify"))
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument(
        "--date-evidence",
        type=Path,
        help="Reviewed completion dates with exact source evidence",
    )
    parser.add_argument(
        "--source-ref", default="HEAD", help="Git revision for inventory"
    )
    parser.add_argument(
        "--split-nested",
        type=Path,
        help="JSON map of reviewed generic child-task line numbers",
    )
    parser.add_argument(
        "--limit",
        type=int,
        help="Apply/verify the first N entries as a resumable pilot",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Validate locally without network or file writes",
    )
    args = parser.parse_args(argv)
    if args.limit is not None and args.limit < 1:
        parser.error("--limit must be positive")
    try:
        if args.operation == "inventory":
            splits = (
                json.loads(args.split_nested.read_text()) if args.split_nested else {}
            )
            dates = (
                json.loads(args.date_evidence.read_text()) if args.date_evidence else {}
            )
            manifest = inventory(ROOT, args.source_ref, splits, dates)
            if not args.dry_run:
                if args.manifest.exists():
                    raise ValueError(
                        "Manifest already exists; do not replace migration checkpoints."
                    )
                save_manifest(args.manifest, manifest)
        else:
            manifest = json.loads(args.manifest.read_text())
            validate(ROOT, manifest, require_sources=args.operation == "apply")
            if not args.dry_run:
                client = Linear(ROOT)
                if args.operation == "apply":
                    apply(
                        client,
                        manifest,
                        lambda: save_manifest(args.manifest, manifest),
                        args.limit,
                    )
                else:
                    count = verify(client, manifest, args.limit)
                    print(
                        f"Verified {count} issues and all configured views against the source manifest."
                    )
        print(
            json.dumps(
                {
                    "entries": len(manifest["entries"]),
                    "states": dict(
                        Counter(entry["state"] for entry in manifest["entries"])
                    ),
                    "dry_run": args.dry_run,
                }
            )
        )
        return 0
    except (
        ValueError,
        KeyError,
        OSError,
        subprocess.SubprocessError,
        LinearError,
    ) as error:
        print(f"backlog-migrate: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
