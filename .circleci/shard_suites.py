#!/usr/bin/env python3
"""Validate suite-level test shards produced from CircleCI timings."""

import argparse
import json
import os
import pathlib
import sys


def read_suites(path):
    suites = [line.strip() for line in path.read_text().splitlines() if line.strip()]
    if len(suites) != len(set(suites)):
        raise ValueError(f"suite list contains duplicate identifiers: {path}")
    return suites


def validate_shard(all_suites, shard_suites, shard_count):
    if shard_count < 1:
        raise ValueError("shard count must be positive")
    if len(all_suites) < shard_count:
        raise ValueError(
            f"cannot assign {len(all_suites)} suites to {shard_count} non-empty shards"
        )
    if not shard_suites:
        raise ValueError("CircleCI assigned no suites to this shard")
    unknown = sorted(set(shard_suites) - set(all_suites))
    if unknown:
        raise ValueError(f"shard contains suites outside the enumeration: {unknown}")


def validate_partition(all_suites, shards):
    for shard in shards:
        validate_shard(all_suites, shard, len(shards))
    flattened = [suite for shard in shards for suite in shard]
    if len(flattened) != len(set(flattened)):
        raise ValueError("suite shards overlap")
    if set(flattened) != set(all_suites):
        raise ValueError("suite shards do not cover the enumeration")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--all", dest="all_path", type=pathlib.Path, required=True)
    parser.add_argument("--shard", type=pathlib.Path, required=True)
    parser.add_argument("--shard-count", type=int, required=True)
    args = parser.parse_args()

    try:
        all_suites = read_suites(args.all_path)
        shard_suites = read_suites(args.shard)
        validate_shard(all_suites, shard_suites, args.shard_count)
    except (OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1) from error

    print(
        "CI_SHARD "
        + json.dumps(
            {
                "index": int(os.environ.get("CIRCLE_NODE_INDEX", "0")),
                "shards": args.shard_count,
                "suites": len(shard_suites),
            },
            separators=(",", ":"),
        )
    )


if __name__ == "__main__":
    main()
