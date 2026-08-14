#!/usr/bin/env python3
"""Discover, validate, select, and rebalance snapshot-suite shards."""

import argparse
import json
import pathlib
import re
import statistics
import sys
import xml.etree.ElementTree as ET


ROOT = pathlib.Path(__file__).resolve().parents[1]
DEFAULT_PLAN = ROOT / ".circleci" / "snapshot-shards.json"
FORMAT_VERSION = 1
SNAPSHOT_TARGET_PATTERN = re.compile(
    r"unitTests\(\s*"
    r'name:\s*"(?P<bundle>[^"]+SnapshotTests)",'
    r".*?"
    r'sources:\s*\["(?P<sources>[^"]+/SnapshotTests)/\*\*"\]',
    re.DOTALL,
)


def load_plan(path):
    try:
        plan = json.loads(path.read_text())
    except FileNotFoundError as error:
        raise ValueError(f"snapshot shard plan does not exist: {path}") from error
    except json.JSONDecodeError as error:
        raise ValueError(f"snapshot shard plan is not valid JSON: {error}") from error
    if plan.get("formatVersion") != FORMAT_VERSION:
        raise ValueError(
            f"unsupported snapshot shard formatVersion {plan.get('formatVersion')}; "
            f"expected {FORMAT_VERSION}"
        )
    if not isinstance(plan.get("shards"), list):
        raise ValueError("snapshot shard plan has no shards")
    return plan


def snapshot_source_roots(repo):
    project = (repo / "Project.swift").read_text()
    roots = {}
    for match in SNAPSHOT_TARGET_PATTERN.finditer(project):
        bundle = match.group("bundle")
        source = match.group("sources")
        if source in roots:
            raise ValueError(f"duplicate snapshot source path in Project.swift: {source}")
        roots[source] = bundle
    if not roots:
        raise ValueError("Project.swift has no snapshot test targets")
    return roots


def source_inventory(repo):
    suites = set()
    for source, bundle in snapshot_source_roots(repo).items():
        root = repo / source
        if not root.is_dir():
            raise ValueError(f"snapshot source path does not exist: {source}")
        for path in sorted(root.rglob("*.swift")):
            text = path.read_text()
            suite = path.stem
            declarations = re.findall(
                r"^(?:(?:private|fileprivate|internal|package|public|final)\s+)*"
                r"(?:struct|class|actor|enum)\s+(\w+Tests)\b",
                text,
                re.MULTILINE,
            )
            if declarations != [suite]:
                relative = path.relative_to(repo)
                found = ", ".join(declarations) if declarations else "none"
                raise ValueError(
                    f"{relative} must declare one top-level suite named {suite}; "
                    f"found {found}"
                )
            identifier = f"{bundle}/{suite}"
            if identifier in suites:
                raise ValueError(f"duplicate snapshot suite in source: {identifier}")
            suites.add(identifier)
    if not suites:
        raise ValueError("snapshot sources contain no test suites")
    return suites


def plan_partition(plan):
    shards = plan["shards"]
    if len(shards) < 1:
        raise ValueError("snapshot shard plan must contain a shard")
    indices = [shard.get("index") for shard in shards]
    if indices != list(range(len(shards))):
        raise ValueError("snapshot shard indices must be consecutive and ordered")
    partition = []
    for shard in shards:
        suites = shard.get("suites")
        if not isinstance(suites, list) or not suites:
            raise ValueError(f"snapshot shard {shard.get('index')} is empty")
        if not all(isinstance(suite, str) and suite for suite in suites):
            raise ValueError(f"snapshot shard {shard.get('index')} has an invalid suite")
        partition.append(suites)
    return partition


def validate_partition(inventory, partition):
    flattened = [suite for shard in partition for suite in shard]
    duplicates = sorted(
        suite for suite in set(flattened) if flattened.count(suite) > 1
    )
    if duplicates:
        raise ValueError(f"snapshot shards overlap: {duplicates}")
    missing = sorted(inventory - set(flattened))
    unknown = sorted(set(flattened) - inventory)
    if missing:
        raise ValueError(f"snapshot shard plan omits suites: {missing}")
    if unknown:
        raise ValueError(f"snapshot shard plan contains unknown suites: {unknown}")


def validate_plan(plan, repo):
    inventory = source_inventory(repo)
    partition = plan_partition(plan)
    validate_partition(inventory, partition)
    return inventory, partition


def read_suites(path):
    suites = [line.strip() for line in path.read_text().splitlines() if line.strip()]
    if len(suites) != len(set(suites)):
        raise ValueError(f"suite list contains duplicate identifiers: {path}")
    return suites


def validate_enumeration(plan, path):
    expected = set(suite for shard in plan_partition(plan) for suite in shard)
    actual = set(read_suites(path))
    if expected != actual:
        missing = sorted(actual - expected)
        stale = sorted(expected - actual)
        details = []
        if missing:
            details.append(f"plan omits {missing}")
        if stale:
            details.append(f"plan contains stale suites {stale}")
        raise ValueError("snapshot enumeration does not match the plan: " + "; ".join(details))


def junit_duration_samples(paths, inventory):
    samples = {suite: [] for suite in inventory}
    documents = []
    for candidate in paths:
        if candidate.is_dir():
            documents.extend(sorted(candidate.rglob("*.xml")))
        else:
            documents.append(candidate)
    if not documents:
        raise ValueError("no JUnit documents were provided")
    for document in documents:
        totals = {}
        try:
            root = ET.parse(document).getroot()
        except (ET.ParseError, OSError) as error:
            raise ValueError(f"cannot read JUnit document {document}: {error}") from error
        for case in root.iter("testcase"):
            suite = case.get("file")
            if not suite:
                continue
            if suite not in inventory:
                raise ValueError(f"JUnit document contains an unknown suite: {suite}")
            try:
                elapsed = float(case.get("time", "0"))
            except ValueError as error:
                raise ValueError(f"JUnit duration is invalid for {suite}") from error
            totals[suite] = totals.get(suite, 0.0) + elapsed
        for suite, elapsed in totals.items():
            samples[suite].append(elapsed)
    missing = sorted(suite for suite, values in samples.items() if not values)
    if missing:
        raise ValueError(f"JUnit documents contain no durations for suites: {missing}")
    return samples, len(documents)


def balanced_partition(weights, shard_count):
    if shard_count < 1:
        raise ValueError("shard count must be positive")
    if len(weights) < shard_count:
        raise ValueError("suite count is less than shard count")
    shards = [[] for _ in range(shard_count)]
    totals = [0.0 for _ in range(shard_count)]
    for suite, elapsed in sorted(weights.items(), key=lambda item: (-item[1], item[0])):
        index = min(range(shard_count), key=lambda value: (totals[value], value))
        shards[index].append(suite)
        totals[index] += elapsed
    for shard in shards:
        shard.sort()
    return shards, totals


def rebalanced_plan(plan, repo, junit_paths):
    inventory, partition = validate_plan(plan, repo)
    samples, document_count = junit_duration_samples(junit_paths, inventory)
    weights = {
        suite: round(statistics.median(values), 3)
        for suite, values in samples.items()
    }
    shards, totals = balanced_partition(weights, len(partition))
    return {
        "formatVersion": FORMAT_VERSION,
        "method": "longest-processing-time over median JUnit suite durations",
        "sampleDocuments": document_count,
        "timings": dict(sorted(weights.items())),
        "shards": [
            {
                "index": index,
                "estimatedSeconds": round(totals[index], 3),
                "suites": suites,
            }
            for index, suites in enumerate(shards)
        ],
    }


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan", type=pathlib.Path, default=DEFAULT_PLAN)
    subparsers = parser.add_subparsers(dest="command", required=True)

    check = subparsers.add_parser("check", help="validate the checked-in plan")
    check.add_argument("--repo", type=pathlib.Path, default=ROOT)

    listing = subparsers.add_parser("list", help="print one shard")
    listing.add_argument("shard", choices=("1", "2"))
    listing.add_argument("--repo", type=pathlib.Path, default=ROOT)

    compare = subparsers.add_parser("compare-enumeration")
    compare.add_argument("--enumeration", type=pathlib.Path, required=True)

    balance = subparsers.add_parser(
        "balance", help="propose a plan from JUnit timing artifacts"
    )
    balance.add_argument("--repo", type=pathlib.Path, default=ROOT)
    balance.add_argument("--junit", type=pathlib.Path, action="append", required=True)
    balance.add_argument("--write", action="store_true")
    return parser.parse_args()


def main():
    args = parse_args()
    try:
        plan = load_plan(args.plan)
        if args.command == "check":
            inventory, partition = validate_plan(plan, args.repo.resolve())
            counts = ", ".join(
                f"{index + 1}={len(suites)}" for index, suites in enumerate(partition)
            )
            print(
                f"Snapshot shard plan is valid: {len(inventory)} suites "
                f"in {len(partition)} shards ({counts})."
            )
        elif args.command == "list":
            _, partition = validate_plan(plan, args.repo.resolve())
            print("\n".join(partition[int(args.shard) - 1]))
        elif args.command == "compare-enumeration":
            validate_enumeration(plan, args.enumeration)
            print("Snapshot enumeration matches the deterministic plan")
        elif args.command == "balance":
            candidate = rebalanced_plan(plan, args.repo.resolve(), args.junit)
            serialized = json.dumps(candidate, indent=2, sort_keys=True) + "\n"
            print(serialized, end="")
            if args.write:
                args.plan.write_text(serialized)
                print(f"Updated {args.plan}")
            else:
                print("Dry run; pass --write to update the plan.")
    except (OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
