#!/usr/bin/env python3
"""Discover, measure, validate, and balance the snapshot test shards."""

from __future__ import annotations

import argparse
import json
import re
import statistics
import subprocess
import sys
import tempfile
from collections import defaultdict
from pathlib import Path
from typing import Iterable


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CONFIG = ROOT / ".github" / "snapshot-shards.json"
REPORT_VERSION = 1
CONFIG_VERSION = 1
SHARD_NAMES = ("1", "2")


class ShardError(RuntimeError):
    """A user-actionable snapshot shard configuration or timing error."""


def _load_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text())
    except OSError as error:
        raise ShardError(f"could not read {path}: {error}") from error
    except json.JSONDecodeError as error:
        raise ShardError(f"invalid JSON in {path}: {error}") from error


def discover_catalog(root: Path = ROOT) -> list[str]:
    """Return every snapshot Bundle/Suite identifier declared by Project.swift."""
    manifest_path = root / "Project.swift"
    try:
        manifest = manifest_path.read_text()
    except OSError as error:
        raise ShardError(f"could not read {manifest_path}: {error}") from error

    declaration = re.compile(r"^ {8}unitTests\(", re.MULTILINE)
    starts = [match.start() for match in declaration.finditer(manifest)] + [len(manifest)]
    bundle_sources: dict[str, Path] = {}
    for index, start in enumerate(starts[:-1]):
        window = manifest[start : starts[index + 1]]
        name = re.search(r'name:\s*"(\w+)"', window)
        sources = re.search(r'sources:\s*\["([^"*]+)\/\*\*"\]', window)
        if name and name.group(1).endswith("SnapshotTests") and sources:
            bundle_sources[name.group(1)] = root / sources.group(1).rstrip("/")

    if not bundle_sources:
        raise ShardError("Project.swift declares no snapshot test bundles")

    catalog: list[str] = []
    for bundle, source_directory in sorted(bundle_sources.items()):
        if not source_directory.is_dir():
            raise ShardError(f"snapshot source directory does not exist: {source_directory}")
        swift_files = sorted(source_directory.rglob("*.swift"))
        if not swift_files:
            raise ShardError(f"snapshot source directory is empty: {source_directory}")
        for source in swift_files:
            suite = source.stem
            text = source.read_text()
            if not re.search(rf"\b(?:struct|class)\s+{re.escape(suite)}\b", text):
                raise ShardError(
                    f"{source.relative_to(root)} must declare suite {suite}; "
                    "snapshot sharding uses one same-named suite per source file"
                )
            catalog.append(f"{bundle}/{suite}")
    return sorted(catalog)


def load_config(path: Path = DEFAULT_CONFIG) -> dict[str, list[str]]:
    data = _load_json(path)
    if data.get("version") != CONFIG_VERSION:
        raise ShardError(
            f"{path} has unsupported version {data.get('version')!r}; "
            f"expected {CONFIG_VERSION}"
        )
    shards = data.get("shards")
    if not isinstance(shards, dict) or set(shards) != set(SHARD_NAMES):
        raise ShardError(f"{path} must contain exactly shards 1 and 2")
    if any(not isinstance(shards[name], list) for name in SHARD_NAMES):
        raise ShardError(f"every shard in {path} must be an array")
    return {name: list(shards[name]) for name in SHARD_NAMES}


def validate_config(catalog: Iterable[str], shards: dict[str, list[str]]) -> None:
    expected = set(catalog)
    assigned = [identifier for name in SHARD_NAMES for identifier in shards[name]]
    counts: dict[str, int] = defaultdict(int)
    for identifier in assigned:
        counts[identifier] += 1

    problems = []
    empty = [name for name in SHARD_NAMES if not shards[name]]
    duplicates = sorted(identifier for identifier, count in counts.items() if count > 1)
    missing = sorted(expected - set(assigned))
    unknown = sorted(set(assigned) - expected)
    if empty:
        problems.append(f"empty shards: {', '.join(empty)}")
    if duplicates:
        problems.append(f"assigned more than once: {', '.join(duplicates)}")
    if missing:
        problems.append(f"missing: {', '.join(missing)}")
    if unknown:
        problems.append(f"unknown: {', '.join(unknown)}")
    if problems:
        raise ShardError("invalid snapshot shard configuration:\n  " + "\n  ".join(problems))


def suites_from_test_results(data: dict) -> dict[str, dict[str, float | int]]:
    suites: dict[str, dict[str, float | int]] = defaultdict(
        lambda: {"durationSeconds": 0.0, "testCount": 0}
    )

    def walk(node: dict, bundle: str | None, suite: str | None) -> None:
        kind = node.get("nodeType")
        name = node.get("name", "")
        if kind == "Unit test bundle":
            bundle = name
        elif kind == "Test Suite":
            suite = name
        elif (
            kind == "Test Case"
            and node.get("result") != "Skipped"
            and bundle
            and suite
            and bundle.endswith("SnapshotTests")
        ):
            identifier = f"{bundle}/{suite}"
            suites[identifier]["durationSeconds"] += float(
                node.get("durationInSeconds") or 0
            )
            suites[identifier]["testCount"] += 1
        for child in node.get("children", []):
            walk(child, bundle, suite)

    for node in data.get("testNodes", []):
        walk(node, None, None)
    return dict(suites)


def make_report(test_results: Iterable[dict]) -> dict:
    combined: dict[str, dict[str, float | int]] = defaultdict(
        lambda: {"durationSeconds": 0.0, "testCount": 0}
    )
    for data in test_results:
        for identifier, row in suites_from_test_results(data).items():
            combined[identifier]["durationSeconds"] += float(row["durationSeconds"])
            combined[identifier]["testCount"] += int(row["testCount"])
    if not combined:
        raise ShardError("the supplied result contains no snapshot test suites")
    return {
        "version": REPORT_VERSION,
        "scheme": "StuffSnapshotTests",
        "suites": [
            {
                "identifier": identifier,
                "durationSeconds": round(float(row["durationSeconds"]), 6),
                "testCount": int(row["testCount"]),
            }
            for identifier, row in sorted(combined.items())
        ],
    }


def load_report(path: Path) -> dict[str, float]:
    data = _load_json(path)
    if data.get("version") != REPORT_VERSION:
        raise ShardError(
            f"{path} has unsupported report version {data.get('version')!r}; "
            f"expected {REPORT_VERSION}"
        )
    rows = data.get("suites")
    if not isinstance(rows, list):
        raise ShardError(f"{path} has no suites array")
    durations: dict[str, float] = {}
    for row in rows:
        try:
            identifier = row["identifier"]
            duration = float(row["durationSeconds"])
            count = int(row["testCount"])
        except (KeyError, TypeError, ValueError) as error:
            raise ShardError(f"{path} contains an invalid suite row: {row!r}") from error
        if identifier in durations:
            raise ShardError(f"{path} contains duplicate suite {identifier}")
        if duration < 0 or count < 1:
            raise ShardError(f"{path} contains invalid timing for {identifier}")
        durations[identifier] = duration
    if not durations:
        raise ShardError(f"{path} contains no suite timings")
    return durations


def balance(durations: dict[str, float]) -> tuple[dict[str, list[str]], dict[str, float]]:
    shards = {name: [] for name in SHARD_NAMES}
    totals = {name: 0.0 for name in SHARD_NAMES}
    for identifier, duration in sorted(durations.items(), key=lambda row: (-row[1], row[0])):
        target = min(SHARD_NAMES, key=lambda name: (totals[name], name))
        shards[target].append(identifier)
        totals[target] += duration
    for name in SHARD_NAMES:
        shards[name].sort()
    return shards, totals


def shard_totals(shards: dict[str, list[str]], durations: dict[str, float]) -> dict[str, float]:
    return {
        name: sum(durations[identifier] for identifier in shards[name])
        for name in SHARD_NAMES
    }


def medians(reports: Iterable[dict[str, float]]) -> dict[str, float]:
    samples: dict[str, list[float]] = defaultdict(list)
    for report in reports:
        for identifier, duration in report.items():
            samples[identifier].append(duration)
    return {identifier: statistics.median(values) for identifier, values in samples.items()}


def combine_shard_reports(
    reports: Iterable[dict[str, float]], expected: set[str]
) -> dict[str, float]:
    combined: dict[str, float] = {}
    for report in reports:
        overlap = sorted(set(combined) & set(report))
        if overlap:
            raise ShardError(f"timing artifacts repeat suites: {', '.join(overlap)}")
        combined.update(report)
    missing = sorted(expected - set(combined))
    unknown = sorted(set(combined) - expected)
    if missing or unknown:
        detail = []
        if missing:
            detail.append(f"missing {', '.join(missing)}")
        if unknown:
            detail.append(f"unknown {', '.join(unknown)}")
        raise ShardError("timing artifacts do not match the catalog: " + "; ".join(detail))
    return combined


def write_config(path: Path, shards: dict[str, list[str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({"version": CONFIG_VERSION, "shards": shards}, indent=2) + "\n")


def _run(command: list[str], *, cwd: Path = ROOT) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, cwd=cwd, text=True, capture_output=True, check=True)


def extract_xcresult(path: Path) -> dict:
    try:
        result = _run(
            [
                "xcrun",
                "xcresulttool",
                "get",
                "test-results",
                "tests",
                "--path",
                str(path),
            ]
        )
        return json.loads(result.stdout)
    except subprocess.CalledProcessError as error:
        detail = error.stderr.strip() or error.stdout.strip() or f"exit {error.returncode}"
        raise ShardError(f"could not read {path}: {detail}") from error
    except json.JSONDecodeError as error:
        raise ShardError(f"xcresulttool returned invalid JSON for {path}: {error}") from error


def reports_from_ci(run_count: int, catalog: list[str]) -> tuple[dict[str, float], int]:
    try:
        listed = _run(
            [
                "gh",
                "run",
                "list",
                "--workflow",
                "CI",
                "--branch",
                "main",
                "--status",
                "success",
                "--limit",
                str(max(50, run_count * 5)),
                "--json",
                "databaseId",
            ]
        )
        runs = json.loads(listed.stdout)
    except (subprocess.CalledProcessError, json.JSONDecodeError) as error:
        raise ShardError(f"could not list successful CI runs with gh: {error}") from error

    complete: list[dict[str, float]] = []
    expected = set(catalog)
    with tempfile.TemporaryDirectory(prefix="snapshot-shards-ci-") as temporary:
        base = Path(temporary)
        for run in runs:
            if len(complete) >= run_count:
                break
            run_id = str(run["databaseId"])
            try:
                shard_reports = []
                for shard in SHARD_NAMES:
                    destination = base / run_id / shard
                    destination.mkdir(parents=True)
                    _run(
                        [
                            "gh",
                            "run",
                            "download",
                            run_id,
                            "--name",
                            f"snapshot-timings-{shard}",
                            "--dir",
                            str(destination),
                        ]
                    )
                    reports = list(destination.rglob("*.json"))
                    if len(reports) != 1:
                        raise ShardError(
                            f"artifact snapshot-timings-{shard} contains "
                            f"{len(reports)} JSON reports"
                        )
                    shard_reports.append(load_report(reports[0]))
                combined = combine_shard_reports(shard_reports, expected)
            except (subprocess.CalledProcessError, ShardError):
                continue
            complete.append(combined)
    if not complete:
        raise ShardError(
            "no successful main CI run has both complete snapshot timing artifacts; "
            "run './snapshot-shards balance --local' instead"
        )
    return medians(complete), len(complete)


def _ensure_complete(durations: dict[str, float], catalog: list[str], source: str) -> None:
    missing = sorted(set(catalog) - set(durations))
    unknown = sorted(set(durations) - set(catalog))
    if missing or unknown:
        detail = []
        if missing:
            detail.append(f"missing {', '.join(missing)}")
        if unknown:
            detail.append(f"unknown {', '.join(unknown)}")
        raise ShardError(f"{source} does not match the current snapshot catalog: {'; '.join(detail)}")


def command_check(args: argparse.Namespace) -> None:
    catalog = discover_catalog()
    shards = load_config(args.config)
    validate_config(catalog, shards)
    print(
        f"Snapshot shard configuration is valid: {len(catalog)} suites "
        f"({len(shards['1'])} in shard 1, {len(shards['2'])} in shard 2)."
    )


def command_list(args: argparse.Namespace) -> None:
    catalog = discover_catalog()
    shards = load_config(args.config)
    validate_config(catalog, shards)
    for identifier in shards[args.shard]:
        print(identifier)


def command_report(args: argparse.Namespace) -> None:
    test_results = [extract_xcresult(path) for path in args.xcresult]
    report = make_report(test_results)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(f"Snapshot suite timing report: {args.output}")


def command_balance(args: argparse.Namespace) -> None:
    catalog = discover_catalog()
    current = load_config(args.config)
    current_error = None
    try:
        validate_config(catalog, current)
    except ShardError as error:
        # A newly added suite is exactly when balancing needs to repair the
        # assignment, so an outdated but structurally readable config must not
        # prevent --local/--report --write from producing its replacement.
        current_error = error

    if args.local:
        with tempfile.TemporaryDirectory(prefix="snapshot-shards-local-") as temporary:
            report = Path(temporary) / "snapshot-suite-durations.json"
            subprocess.run(
                ["./test", "--snapshots", "--timing-report", str(report)],
                cwd=ROOT,
                check=True,
            )
            durations = load_report(report)
        source = "local snapshot run"
    elif args.ci:
        durations, samples = reports_from_ci(args.runs, catalog)
        source = f"median of {samples} complete successful main CI run(s)"
    else:
        durations = load_report(args.report)
        source = str(args.report)

    _ensure_complete(durations, catalog, source)
    proposed, proposed_totals = balance(durations)
    print(f"Timing source: {source}")
    if current_error:
        print(f"Current assignment is stale: {current_error}")
    else:
        current_totals = shard_totals(current, durations)
        print(
            "Current estimated shard time: "
            f"1={current_totals['1']:.3f}s, 2={current_totals['2']:.3f}s"
        )
    print(
        "Proposed estimated shard time: "
        f"1={proposed_totals['1']:.3f}s, 2={proposed_totals['2']:.3f}s"
    )
    print(json.dumps({"version": CONFIG_VERSION, "shards": proposed}, indent=2))
    if args.write:
        write_config(args.config, proposed)
        print(f"Updated {args.config}")
    else:
        print("Dry run; pass --write to update the configuration.")


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    commands = result.add_subparsers(dest="command", required=True)

    check = commands.add_parser("check", help="validate the checked-in shard assignment")
    check.set_defaults(function=command_check)

    listing = commands.add_parser("list", help="print Bundle/Suite identifiers for one shard")
    listing.add_argument("shard", choices=SHARD_NAMES)
    listing.set_defaults(function=command_list)

    report = commands.add_parser("report", help="write a timing report from .xcresult data")
    report.add_argument("--xcresult", action="append", type=Path, required=True)
    report.add_argument("--output", type=Path, required=True)
    report.set_defaults(function=command_report)

    balancing = commands.add_parser("balance", help="propose a duration-balanced assignment")
    source = balancing.add_mutually_exclusive_group(required=True)
    source.add_argument("--local", action="store_true", help="run the full local snapshot suite")
    source.add_argument("--ci", action="store_true", help="use successful main CI artifacts")
    source.add_argument("--report", type=Path, help="use an existing timing report")
    balancing.add_argument("--runs", type=int, default=10, help="complete CI runs to sample (default: 10)")
    balancing.add_argument("--write", action="store_true", help="update the config instead of only reporting")
    balancing.set_defaults(function=command_balance)
    return result


def main() -> int:
    args = parser().parse_args()
    if getattr(args, "runs", 1) < 1:
        print("error: --runs must be at least 1", file=sys.stderr)
        return 2
    try:
        args.function(args)
    except ShardError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    except subprocess.CalledProcessError as error:
        print(f"error: command failed with exit {error.returncode}: {' '.join(error.cmd)}", file=sys.stderr)
        return error.returncode or 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
