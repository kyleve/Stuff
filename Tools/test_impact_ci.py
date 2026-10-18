#!/usr/bin/env python3
"""CircleCI adapter for explicit experiment pipelines; ordinary CI never filters."""

import argparse
import hashlib
import os
from pathlib import Path
import shlex
import sys

from test_impact import ROOT, DEFAULT_SELECTOR, collect, environment, git, load, make_plan, revision, tool_key, write_json
from test_impact_graph import digest
from test_impact_selection import filtered_assignment


def prepare(mode, base, bash_env):
    directory = ROOT / ".build/test-impact"
    directory.mkdir(parents=True, exist_ok=True)
    head = revision("HEAD")
    try:
        merge_base = git("merge-base", revision(base), head)
    except ValueError as error:
        print("warning: cannot resolve experiment base; plans will select everything: " + str(error), file=sys.stderr)
        merge_base = "unavailable"
    (directory / "head-key").write_text(head)
    (directory / "base-key").write_text(merge_base)
    (directory / "tool-key").write_text(tool_key())
    (directory / "tool-variant-key").write_text("target" if mode == "target" else "indexed")
    # A later run can acquire previously unavailable base metadata. Never let an
    # immutable CircleCI cache substitute that earlier run's wider plan.
    (directory / "run-key").write_text(digest({"head": head, "base": merge_base, "mode": mode,
                                               "tools": tool_key(), "workflow": os.environ.get("CIRCLE_WORKFLOW_ID", "local")}))
    if mode in {"snapshot", "shadow"} and bash_env:
        with Path(bash_env).open("a") as output:
            output.write("export TEST_IMPACT_INDEX_STORE=" + shlex.quote(str(directory / "build-index")) + "\n")


def build_plans(mode, base):
    directory = ROOT / ".build/test-impact"
    head = revision("HEAD")
    merge_base = (directory / "base-key").read_text()
    metadata = directory / "history" / (head + ".json")
    base_metadata = directory / "history" / (merge_base + ".json")
    plans = directory / "plans" / (directory / "run-key").read_text()
    for selection_mode in ("full", "target", "snapshot"):
        make_plan(metadata, base, head, selection_mode, plans / (selection_mode + ".json"),
                  base_metadata if base_metadata.exists() else None)


def worker(mode, kind, assignment, output):
    if mode not in {"target", "snapshot"}:
        if kind == "snapshot":
            output.write_text(assignment.read_text())
        return
    directory = ROOT / ".build/test-impact"
    plan_path = directory / "plans" / (directory / "run-key").read_text() / (mode + ".json")
    plan = load(plan_path)
    expected = environment()
    if kind == "snapshot":
        selected = filtered_assignment(plan, assignment.read_text().splitlines(), revision("HEAD"), expected)
    else:
        # Reuse the same identity/inventory guards even when selecting unit bundles.
        filtered_assignment(plan, [], revision("HEAD"), expected)
        selected = plan["units"]
        if len(selected) != len(set(selected)) or not set(selected) <= set(plan["selectedBundles"]):
            raise ValueError("invalid selected unit bundles")
    output.write_text("".join(name + "\n" for name in selected))


def evidence(mode, directory, output):
    if mode == "off":
        return
    files = sorted(directory.rglob("*.xml"))
    if not files or not os.environ.get("CIRCLE_WORKFLOW_ID"):
        raise ValueError("evidence requires JUnit files and the CircleCI workflow identity")
    write_json(output, {"revision": revision("HEAD"), "mode": mode, "environment": environment(),
                        "workflowID": os.environ["CIRCLE_WORKFLOW_ID"], "jobURL": os.environ.get("CIRCLE_BUILD_URL"),
                        "junit": [{"path": str(path.relative_to(output.parent)),
                                   "sha256": hashlib.sha256(path.read_bytes()).hexdigest()} for path in files]})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("prepare", "collect", "plan", "worker", "evidence"))
    parser.add_argument("--mode", choices=("off", "full", "target", "snapshot", "shadow"), required=True)
    parser.add_argument("--base", default="origin/main")
    parser.add_argument("--bash-env", type=Path)
    parser.add_argument("--kind", choices=("unit", "snapshot"))
    parser.add_argument("--assignment", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--junit-directory", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "prepare":
            prepare(args.mode, args.base, args.bash_env)
        elif args.command == "collect":
            directory = ROOT / ".build/test-impact"
            collect(directory / "history" / (revision("HEAD") + ".json"), DEFAULT_SELECTOR,
                    directory / "build-index" if args.mode in {"snapshot", "shadow"} else None,
                    build_manifest=ROOT / "ci-test-build/manifest.json")
        elif args.command == "plan":
            build_plans(args.mode, args.base)
        elif args.command == "worker":
            if not args.kind or not args.output or (args.kind == "snapshot" and not args.assignment):
                raise ValueError("worker needs kind, output, and a snapshot assignment")
            worker(args.mode, args.kind, args.assignment, args.output)
        elif args.command == "evidence":
            if not args.junit_directory or not args.output:
                raise ValueError("evidence needs a JUnit directory and output path")
            evidence(args.mode, args.junit_directory, args.output)
        return 0
    except (ValueError, OSError, KeyError) as error:
        print("test impact CI: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
