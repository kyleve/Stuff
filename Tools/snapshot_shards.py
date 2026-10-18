#!/usr/bin/env python3
"""Discover, validate, select, and rebalance snapshot-suite shards."""

import argparse
import json
import math
import pathlib
import re
import statistics
import sys
import xml.etree.ElementTree as ET

from repository import repository_root


ROOT = repository_root(__file__)
DEFAULT_PLAN = ROOT / ".circleci" / "snapshot-shards.json"
FORMAT_VERSION = 1
# Minimum reduction in the slowest worker required to move existing suites.
MINIMUM_IMPROVEMENT = 0.05
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


def validate_partition(inventory, partition, allow_missing=False):
    flattened = [suite for shard in partition for suite in shard]
    duplicates = sorted(
        suite for suite in set(flattened) if flattened.count(suite) > 1
    )
    if duplicates:
        raise ValueError(f"snapshot shards overlap: {duplicates}")
    missing = sorted(inventory - set(flattened))
    unknown = sorted(set(flattened) - inventory)
    if missing and not allow_missing:
        raise ValueError(f"snapshot shard plan omits suites: {missing}")
    if unknown:
        raise ValueError(f"snapshot shard plan contains unknown suites: {unknown}")
    return missing


def validate_plan(plan, repo):
    inventory = source_inventory(repo)
    partition = plan_partition(plan)
    validate_partition(inventory, partition)
    return inventory, partition


def execution_partition(plan, repo):
    inventory = source_inventory(repo)
    partition = plan_partition(plan)
    intake = validate_partition(inventory, partition, allow_missing=True)
    return inventory, [*partition, intake]


def selected_shard(partition, shard_number, worker_count=None):
    if worker_count is not None and worker_count != len(partition):
        raise ValueError(
            f"CircleCI started {worker_count} workers, but the plan has "
            f"{len(partition)} shards"
        )
    if shard_number < 1 or shard_number > len(partition):
        raise ValueError(
            f"shard number {shard_number} is outside 1...{len(partition)}"
        )
    return partition[shard_number - 1]


def read_suites(path):
    suites = [line.strip() for line in path.read_text().splitlines() if line.strip()]
    if len(suites) != len(set(suites)):
        raise ValueError(f"suite list contains duplicate identifiers: {path}")
    return suites


def validate_enumeration(expected, path):
    expected = set(expected)
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


def validate_execution(assignment_path, junit_path):
    expected = set(read_suites(assignment_path))
    try:
        root = ET.parse(junit_path).getroot()
    except (ET.ParseError, OSError) as error:
        raise ValueError(f"cannot read JUnit document {junit_path}: {error}") from error

    actual = set()
    for case in root.iter("testcase"):
        suite = case.get("file")
        if not suite:
            raise ValueError(f"JUnit test case has no suite identifier: {junit_path}")
        actual.add(suite)

    missing = sorted(expected - actual)
    unexpected = sorted(actual - expected)
    if missing or unexpected:
        details = []
        if missing:
            details.append(f"did not execute {missing}")
        if unexpected:
            details.append(f"executed unassigned suites {unexpected}")
        raise ValueError("snapshot execution does not match the assignment: " + "; ".join(details))
    return len(actual)


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
    if len({path.resolve() for path in documents}) != len(documents):
        raise ValueError("duplicate JUnit documents were provided")
    for document in documents:
        totals = {}
        try:
            root = ET.parse(document).getroot()
        except (ET.ParseError, OSError) as error:
            raise ValueError(f"cannot read JUnit document {document}: {error}") from error
        for node in root.iter():
            if node.tag in ("failure", "error", "skipped"):
                raise ValueError(f"JUnit document contains {node.tag}: {document}")
            for attribute in ("failures", "errors", "skipped"):
                if float(node.get(attribute, "0")) != 0:
                    raise ValueError(f"JUnit document contains {attribute}: {document}")
        for case in root.iter("testcase"):
            suite = case.get("file")
            if not suite:
                raise ValueError(f"JUnit test case has no suite identifier: {document}")
            if suite not in inventory:
                raise ValueError(f"JUnit document contains an unknown suite: {suite}")
            try:
                elapsed = float(case.get("time", "nan"))
            except ValueError as error:
                raise ValueError(f"JUnit duration is invalid for {suite}") from error
            if not math.isfinite(elapsed) or elapsed < 0:
                raise ValueError(f"JUnit duration is invalid for {suite}")
            totals[suite] = totals.get(suite, 0.0) + elapsed
            if not math.isfinite(totals[suite]):
                raise ValueError(f"JUnit duration total is invalid for {suite}")
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
        index = min(range(shard_count), key=lambda value: (totals[value], bool(shards[value]), value))
        shards[index].append(suite)
        totals[index] += elapsed
    for shard in shards:
        shard.sort()
    return shards, totals


def partition_totals(partition, weights):
    return [round(sum(weights[suite] for suite in shard), 3) for shard in partition]


def assignment_plan(partition):
    """Persist execution policy only; measurements belong in the balance report."""
    return {
        "formatVersion": FORMAT_VERSION,
        "shards": [
            {"index": index, "suites": sorted(suites)}
            for index, suites in enumerate(partition)
        ],
    }


def stable_partition(partition, weights):
    """Place intake first, then stop single-suite moves at the 5% target.

    Greedy moves strictly reduce the maximum load and never move a suite twice.
    This is a bounded local search, not a globally minimum-move solver. If the
    target is unreachable this way, discard all moves of existing suites.
    """
    shards = [list(suites) for suites in partition[:-1]]
    totals = partition_totals(shards, weights)
    for suite in sorted(partition[-1], key=lambda suite: (-weights[suite], suite)):
        index = min(range(len(shards)), key=lambda index: (totals[index], index))
        shards[index].append(suite)
        totals[index] = round(totals[index] + weights[suite], 3)
    intake_only = [list(suites) for suites in shards]
    baseline = max(partition_totals(partition, weights))
    target = baseline * (1 - MINIMUM_IMPROVEMENT)
    remaining = {suite for shard in partition[:-1] for suite in shard}
    while max(totals) > target + 1e-9:
        best = None
        for source, suites in enumerate(shards):
            if len(suites) == 1:
                continue
            for suite in sorted(remaining.intersection(suites)):
                for destination in range(len(shards)):
                    if source == destination:
                        continue
                    candidate = list(totals)
                    candidate[source] = round(candidate[source] - weights[suite], 3)
                    candidate[destination] = round(candidate[destination] + weights[suite], 3)
                    if max(candidate) >= max(totals):
                        continue
                    key = (max(candidate), suite, source, destination)
                    if best is None or key < best:
                        best = key
        if best is None:
            return intake_only
        _, suite, source, destination = best
        shards[source].remove(suite)
        shards[destination].append(suite)
        remaining.remove(suite)
        totals = partition_totals(shards, weights)
    return shards


def rebalance_report(plan, repo, junit_paths, shard_count=None):
    inventory, partition = execution_partition(plan, repo)
    samples, document_count = junit_duration_samples(junit_paths, inventory)
    weights = {
        suite: round(statistics.median(values), 3)
        for suite, values in samples.items()
    }
    planned_count = len(partition) - 1
    requested_count = planned_count if shard_count is None else shard_count
    full_partition, _ = balanced_partition(weights, requested_count)
    count_changed = requested_count != planned_count
    shards = full_partition if count_changed else stable_partition(partition, weights)
    validate_partition(inventory, shards)
    before = partition_totals(partition, weights)
    after = partition_totals([*shards, []], weights)
    original = {suite: index for index, shard in enumerate(partition[:-1]) for suite in shard}
    proposed = {suite: index for index, shard in enumerate(shards) for suite in shard}
    moves = [
        {"suite": suite, "fromWorker": original[suite] + 1, "toWorker": proposed[suite] + 1}
        for suite in sorted(original)
        if original[suite] != proposed[suite]
    ]
    changed = bool(partition[-1] or moves or count_changed)
    return {
        "plan": assignment_plan(shards),
        "changed": changed,
        "reason": (
            "shard count changed" if count_changed else
            "intake assigned" if partition[-1] else
            "improvement threshold reached" if moves else
            "no qualifying single-suite rebalance"
        ),
        "beforeSeconds": before,
        "afterSeconds": after,
        "improvementPercent": round(100 * (max(before) - max(after)) / max(before), 3) if max(before) else 0,
        "fullRebalanceSeconds": partition_totals(full_partition, weights),
        "intakeSuites": partition[-1],
        "movedSuites": moves,
        "sampleDocuments": document_count,
        "samplesPerSuite": {suite: len(samples[suite]) for suite in sorted(samples)},
        "timings": dict(sorted(weights.items())),
    }


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan", type=pathlib.Path, default=DEFAULT_PLAN)
    subparsers = parser.add_subparsers(dest="command", required=True)

    check = subparsers.add_parser("check", help="validate the checked-in plan")
    check.add_argument("--repo", type=pathlib.Path, default=ROOT)

    listing = subparsers.add_parser("list", help="print one shard")
    listing.add_argument("shard", type=int)
    listing.add_argument("--repo", type=pathlib.Path, default=ROOT)
    listing.add_argument("--total", type=int)

    compare = subparsers.add_parser("compare-enumeration")
    compare.add_argument("--enumeration", type=pathlib.Path, required=True)

    verify = subparsers.add_parser("verify-execution")
    verify.add_argument("--assignment", type=pathlib.Path, required=True)
    verify.add_argument("--junit", type=pathlib.Path, required=True)

    balance = subparsers.add_parser(
        "balance", help="report measured loads and propose stable assignments"
    )
    balance.add_argument("--repo", type=pathlib.Path, default=ROOT)
    balance.add_argument("--junit", type=pathlib.Path, action="append", required=True)
    balance.add_argument("--shards", type=int, help="explicitly change the planned count using a full rebalance")
    balance.add_argument("--write", action="store_true", help="write assignments only when a rebalance qualifies")
    return parser.parse_args()


def main():
    args = parse_args()
    try:
        plan = load_plan(args.plan)
        if args.command == "check":
            inventory, partition = execution_partition(plan, args.repo.resolve())
            counts = ", ".join(
                f"{index + 1}={len(suites)}" for index, suites in enumerate(partition)
            )
            print(
                f"Snapshot shard plan is valid: {len(inventory)} suites "
                f"in {len(partition) - 1} planned shards plus intake ({counts})."
            )
        elif args.command == "list":
            _, partition = execution_partition(plan, args.repo.resolve())
            selected = selected_shard(partition, args.shard, args.total)
            sys.stdout.write("".join(f"{suite}\n" for suite in selected))
        elif args.command == "compare-enumeration":
            inventory, _ = execution_partition(plan, ROOT)
            validate_enumeration(inventory, args.enumeration)
            print("Snapshot enumeration matches the deterministic plan")
        elif args.command == "verify-execution":
            count = validate_execution(args.assignment, args.junit)
            print(f"Snapshot execution matches the assignment: {count} suites")
        elif args.command == "balance":
            report = rebalance_report(
                plan, args.repo.resolve(), args.junit, args.shards
            )
            print(json.dumps(report, indent=2, sort_keys=True))
            if args.write and report["changed"]:
                args.plan.write_text(json.dumps(report["plan"], indent=2, sort_keys=True) + "\n")
                print(f"Updated {args.plan}", file=sys.stderr)
            elif args.write:
                print("No rebalance needed; plan unchanged.", file=sys.stderr)
            else:
                print("Dry run; pass --write to apply a qualifying rebalance.", file=sys.stderr)
    except (OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
