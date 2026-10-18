#!/usr/bin/env python3
"""Opt-in test selection experiment behind ``./test --impact``. Never changes normal scope."""

import argparse
import hashlib
import fcntl
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.request

from repository import repository_root
from snapshot_shards import source_inventory
from test_impact_graph import VERSION, SELECTOR_VERSION, SELECTOR_SHA256, catalog, digest
from test_impact_selection import filtered_assignment, select, validate_metadata
from test_impact_experiment import comparison, finish, new_ledger, reserve, shadow_audit


ROOT = repository_root(__file__)
DEFAULT_SELECTOR = ROOT / ".build/test-impact/vendor/xcode-selective-test"
INDEX_BINARY = ROOT / ".build/test-impact/bin/test-impact-index"
SELECTOR_BINARY_SHA256 = "e840789ef752872d06f3a152672f3475a6660993c57af14d92c43e4eb3fc1eab"


def run(argv, root=ROOT, input_text=None):
    result = subprocess.run([str(arg) for arg in argv], cwd=root, input=input_text,
                            capture_output=True, text=True)
    if result.returncode:
        raise ValueError(f"{argv[0]} failed ({result.returncode}): {result.stderr[-4000:]}")
    return result.stdout


def git(*args, root=ROOT):
    return run(["git", *args], root=root).strip()


def revision(ref, root=ROOT):
    return git("rev-parse", "--verify", "--end-of-options", ref + "^{commit}", root=root)


def tracked_blobs(ref="HEAD", root=ROOT):
    entries = run(["git", "ls-tree", "-rz", "--full-tree", ref], root=root).split("\0")
    result = {}
    for entry in entries:
        if entry:
            header, path = entry.split("\t", 1)
            mode, kind, blob = header.split()
            if kind != "blob":
                raise ValueError("unmodeled repository entry: " + path)
            result[path] = mode + ":" + blob
    return result


def environment(root=ROOT):
    expected = (root / ".xcode-build-version").read_text().strip()
    actual = run(["xcodebuild", "-version"], root=root).split("Build version ")[-1].strip()
    if expected != actual:
        raise ValueError(f"expected Xcode {expected}, found {actual}")
    return {"xcode": actual, "sdk": run(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-build-version"]).strip(),
            "architecture": platform.machine(), "configuration": "Debug",
            "selector": SELECTOR_VERSION, "analysisVersion": VERSION, "analysisKey": tool_key()}


def write_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    # A result must be complete before a watcher or worker can consume it.
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as temporary:
        json.dump(value, temporary, indent=2, sort_keys=True)
        temporary.write("\n")
        name = temporary.name
    os.replace(name, path)


def load(path):
    return json.loads(Path(path).read_text())


def bootstrap(selector=DEFAULT_SELECTOR, target_only=False):
    selector = Path(selector)
    if not selector.exists():
        url = f"https://github.com/mikeger/XcodeSelectiveTesting/releases/download/{SELECTOR_VERSION}/xcode-selective-test.tar.gz"
        with urllib.request.urlopen(url, timeout=90) as response:
            data = response.read()
        if hashlib.sha256(data).hexdigest() != SELECTOR_SHA256:
            raise ValueError("selector release checksum mismatch")
        selector.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryFile() as archive:
            archive.write(data)
            archive.seek(0)
            with tarfile.open(fileobj=archive, mode="r:gz") as bundle:
                member = bundle.getmember("xcode-selective-test")
                if not member.isfile():
                    raise ValueError("selector release is not a regular executable")
                contents = bundle.extractfile(member).read()
                selector.write_bytes(contents)
                selector.chmod(0o755)
    if hashlib.sha256(selector.read_bytes()).hexdigest() != SELECTOR_BINARY_SHA256:
        raise ValueError("installed selector checksum mismatch")
    if target_only:
        return
    key = tool_key()
    stamp = INDEX_BINARY.with_suffix(".json")
    if INDEX_BINARY.exists() and stamp.exists():
        previous = load(stamp)
        if previous == {"key": key, "sha256": hashlib.sha256(INDEX_BINARY.read_bytes()).hexdigest()}:
            return
    run(["swift", "build", "--package-path", "Tools/TestImpact", "--force-resolved-versions", "--product", "test-impact-index"])
    directory = run(["swift", "build", "--package-path", "Tools/TestImpact", "--show-bin-path"]).strip()
    INDEX_BINARY.parent.mkdir(parents=True, exist_ok=True)
    INDEX_BINARY.write_bytes((Path(directory) / "test-impact-index").read_bytes())
    INDEX_BINARY.chmod(0o755)
    write_json(stamp, {"key": key, "sha256": hashlib.sha256(INDEX_BINARY.read_bytes()).hexdigest()})


def tool_key():
    paths = [ROOT / "Tools/TestImpact/Package.swift", ROOT / "Tools/TestImpact/Package.resolved",
             ROOT / "Tools/snapshot_shards.py", ROOT / "Tools/repository.py"]
    paths += sorted((ROOT / "Tools/TestImpact/Sources").glob("*.swift"))
    paths += sorted((ROOT / "Tools").glob("test_impact*.py"))
    return digest({str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths})


def collect(output, selector, index_store=None, allow_dirty=False, root=ROOT, build_manifest=None):
    started = time.monotonic()
    commit = revision("HEAD", root)
    dirty = bool(git("status", "--porcelain", "--untracked-files=no", root=root))
    if dirty and not allow_dirty:
        raise ValueError("commit changes before collecting revision-bound metadata")
    blobs = tracked_blobs(root=root)
    with tempfile.TemporaryDirectory(prefix="test-impact-graph-") as directory:
        run(["mise", "exec", "--", "tuist", "graph", "--format", "json", "--no-open", "--output-path", directory], root=root)
        graph = load(Path(directory) / "graph.json")
    package = json.loads(run(["swift", "package", "dump-package"], root=root))
    selector_process = subprocess.run([str(Path(selector).resolve()), "Stuff.xcworkspace", "--dry-run", "--dot",
                                       "--changed-files", "README.md"], cwd=root, capture_output=True, text=True)
    if selector_process.returncode:
        raise ValueError("XcodeSelectiveTesting failed: " + selector_process.stderr[-4000:])
    result = {"version": VERSION, "revision": commit, "dirty": dirty, "environment": environment(root),
              "blobs": blobs, "catalog": catalog(root, graph, package, selector_process.stdout, blobs),
              "index": [], "indexDiagnostics": [], "selectorDiagnostics": selector_process.stderr}
    if set(result["catalog"]["suites"]) != source_inventory(root):
        raise ValueError("generated graph does not match the canonical snapshot suite inventory")
    untracked_sources = {path for bundle in result["catalog"]["bundles"].values()
                         for path in bundle["sources"] if path not in blobs}
    if untracked_sources:
        raise ValueError("generated graph contains untracked source inputs: " + ", ".join(sorted(untracked_sources)))
    if index_store:
        if build_manifest:
            manifest = load(build_manifest)
            expected = {"commit": commit, "xcodeBuild": result["environment"]["xcode"],
                        "sdkBuild": result["environment"]["sdk"], "configuration": "Debug",
                        "architecture": result["environment"]["architecture"]}
            if any(manifest.get(key) != value for key, value in expected.items()):
                raise ValueError("compiler index build manifest does not match this revision/environment")
            if not {"Stuff-iOS-Tests", "StuffSnapshotTests"} <= set(manifest.get("schemes", {})):
                raise ValueError("index requires both complete iOS test schemes")
            result["indexRevision"] = commit
        elif not allow_dirty:
            raise ValueError("indexed collection requires --build-manifest from the shared build")
        files = sorted(set().union(*(set(bundle["sources"]) for bundle in result["catalog"]["bundles"].values()
                                    if bundle["platform"] == "iOS")))
        compiler = Path(run(["xcrun", "--find", "swiftc"]).strip())
        with tempfile.TemporaryDirectory(prefix="test-impact-db-") as database:
            request = {"root": str(root.resolve()), "files": files, "indexStore": str(Path(index_store).resolve()),
                       "database": database, "library": str(compiler.parent.parent / "lib/libIndexStore.dylib")}
            try:
                result["index"] = json.loads(run([INDEX_BINARY], input_text=json.dumps(request)))
            except ValueError as error:
                result["indexDiagnostics"].append(str(error))
                print("warning: compiler analysis unavailable; retaining target selection: " + str(error), file=sys.stderr)
    result["seconds"] = round(time.monotonic() - started, 3)
    write_json(output, result)
    return result


def make_plan(metadata_path, base_ref, head_ref, mode, output, base_metadata=None, root=ROOT):
    started = time.monotonic()
    head = load(metadata_path)
    head_revision = revision(head_ref, root)
    validate_metadata(head, head_revision)
    if head["blobs"] != tracked_blobs(head_revision, root):
        raise ValueError("head metadata source tree mismatch")
    fallback = None
    base = None
    changed = []
    merge_base = None
    try:
        base_revision = revision(base_ref, root)
        merge_base = git("merge-base", base_revision, head_revision, root=root)
        changed = sorted(set(run(["git", "diff", "--name-only", "--no-renames", "-z", merge_base, head_revision], root=root).rstrip("\0").split("\0")) - {""})
        if base_metadata:
            base = load(base_metadata)
            validate_metadata(base, merge_base, head["environment"])
            if base["blobs"] != tracked_blobs(merge_base, root):
                raise ValueError("base metadata source tree mismatch")
        else:
            raise ValueError("merge-base metadata unavailable")
    except (ValueError, OSError, KeyError) as error:
        base = None
        fallback = str(error)
    plan = select(head, base, changed, mode, fallback)
    plan["mergeBase"] = merge_base
    plan["analysisSeconds"] = round(time.monotonic() - started, 3)
    plan["collectionSeconds"] = head["seconds"]
    write_json(output, plan)
    lines = [f"# Test selection: {mode}", "", f"Revision: `{head_revision}`", "",
             f"Selected {len(plan['units'])} iOS unit bundles and {len(plan['snapshots'])}/{len(plan['snapshotInventory'])} snapshot suites.",
             "", "Experimental evidence only. Normal CI remains authoritative.", ""]
    lines.extend("- " + reason for reason in plan["reasons"])
    Path(str(output) + ".md").write_text("\n".join(lines) + "\n")
    print("\n".join(lines), file=sys.stderr)
    return plan


def parser():
    result = argparse.ArgumentParser(description=__doc__)
    commands = result.add_subparsers(dest="command", required=True)
    setup = commands.add_parser("bootstrap", help="install pinned analysis tools into ignored build directories")
    setup.add_argument("--selector", type=Path, default=DEFAULT_SELECTOR)
    setup.add_argument("--target-only", action="store_true", help="omit the unused compiler-index tool for target mode")
    collect_parser = commands.add_parser("collect", help="collect current generated-project and optional compiler metadata")
    collect_parser.add_argument("--output", type=Path, required=True)
    collect_parser.add_argument("--selector", type=Path, default=DEFAULT_SELECTOR)
    collect_parser.add_argument("--index-store", type=Path)
    collect_parser.add_argument("--build-manifest", type=Path)
    collect_parser.add_argument("--allow-dirty", action="store_true", help="diagnostics only; plans reject this metadata")
    plan_parser = commands.add_parser("plan", help="plan an explicit base/head comparison without running tests")
    plan_parser.add_argument("--metadata", type=Path, required=True)
    plan_parser.add_argument("--base-metadata", type=Path)
    plan_parser.add_argument("--base", required=True)
    plan_parser.add_argument("--head", required=True)
    plan_parser.add_argument("--mode", choices=("full", "target", "snapshot"), required=True)
    plan_parser.add_argument("--output", type=Path, required=True)
    filter_parser = commands.add_parser("filter", help="intersect an experimental snapshot assignment")
    filter_parser.add_argument("--plan", type=Path, required=True)
    filter_parser.add_argument("--assignment", type=Path, required=True)
    filter_parser.add_argument("--output", type=Path, required=True)
    commands.add_parser("tool-key", help="print the analysis binary cache fingerprint")
    audit = commands.add_parser("audit", help="compare a shadow plan with complete snapshot JUnit evidence")
    audit.add_argument("--plan", type=Path, required=True)
    audit.add_argument("--junit", type=Path, nargs="+", required=True)
    audit.add_argument("--evidence", type=Path, nargs="+", required=True,
                       help="worker impact-evidence.json files from the same full/shadow workflow")
    audit.add_argument("--verdicts", type=Path)
    audit.add_argument("--output", type=Path, required=True)
    replay = commands.add_parser("replay", help="replay first-parent main changes with revision-matched metadata")
    replay.add_argument("--ref", default="origin/main")
    replay.add_argument("--count", type=int, default=100)
    replay.add_argument("--metadata-directory", type=Path, required=True)
    replay.add_argument("--output", type=Path, required=True)
    budget = commands.add_parser("budget", help="reserve and reconcile the $250 experiment budget")
    budget.add_argument("--ledger", type=Path, required=True)
    actions = budget.add_subparsers(dest="action", required=True)
    initialize = actions.add_parser("init")
    initialize.add_argument("--baseline", required=True)
    reservation = actions.add_parser("reserve")
    reservation.add_argument("--key", required=True)
    reservation.add_argument("--revision", required=True)
    reservation.add_argument("--mode", choices=("full", "target", "snapshot", "shadow"), required=True)
    reservation.add_argument("--category", choices=("leaf-ui", "shared-core", "installer", "docs", "broad"), required=True)
    reservation.add_argument("--repetition", type=int, choices=(1, 2), required=True)
    terminal = actions.add_parser("finish")
    terminal.add_argument("--key", required=True)
    terminal.add_argument("--result", type=Path, required=True)
    actions.add_parser("report")
    return result


def main(argv=None):
    args = parser().parse_args(argv)
    try:
        if args.command == "bootstrap":
            bootstrap(args.selector, args.target_only)
        elif args.command == "collect":
            collect(args.output, args.selector, args.index_store, args.allow_dirty, build_manifest=args.build_manifest)
        elif args.command == "plan":
            make_plan(args.metadata, args.base, args.head, args.mode, args.output, args.base_metadata)
        elif args.command == "filter":
            assignment = args.assignment.read_text().splitlines()
            selected = filtered_assignment(load(args.plan), assignment, revision("HEAD"), environment())
            args.output.write_text("".join(suite + "\n" for suite in selected))
        elif args.command == "tool-key":
            print(tool_key())
        elif args.command == "audit":
            write_json(args.output, shadow_audit(load(args.plan), args.junit,
                                               load(args.verdicts) if args.verdicts else {}, args.evidence))
        elif args.command == "replay":
            if not 1 <= args.count <= 100:
                raise ValueError("replay count must be between 1 and 100")
            commits = git("rev-list", "--first-parent", f"--max-count={args.count}", revision(args.ref)).splitlines()
            rows = []
            for commit in reversed(commits):
                parent = revision(commit + "^")
                head_path = args.metadata_directory / (commit + ".json")
                base_path = args.metadata_directory / (parent + ".json")
                row = {"revision": commit, "base": parent}
                if not head_path.exists() or not base_path.exists():
                    row.update({"fallback": "historical metadata unavailable", "estimatedSavings": None})
                else:
                    with tempfile.TemporaryDirectory() as directory:
                        row["plans"] = {mode: make_plan(head_path, parent, commit, mode,
                                                        Path(directory) / (mode + ".json"), base_path)
                                        for mode in ("target", "snapshot")}
                rows.append(row)
            write_json(args.output, {"changes": rows, "qualified": sum(
                "plans" in row and all(plan["base"] is not None for plan in row["plans"].values()) for row in rows),
                                     "warning": "Missing historical metadata is not evidence of savings."})
        elif args.command == "budget":
            args.ledger.parent.mkdir(parents=True, exist_ok=True)
            with args.ledger.with_suffix(".lock").open("a") as lock:
                fcntl.flock(lock, fcntl.LOCK_EX)
                if args.action == "init":
                    if args.ledger.exists():
                        raise ValueError("experiment ledger already exists")
                    ledger = new_ledger(revision(args.baseline))
                else:
                    ledger = load(args.ledger)
                if args.action == "reserve":
                    reserve(ledger, args.key, revision(args.revision), args.mode, args.category, args.repetition)
                elif args.action == "finish":
                    finish(ledger, args.key, load(args.result))
                elif args.action == "report":
                    print(json.dumps(comparison(ledger), indent=2))
                    return 0
                write_json(args.ledger, ledger)
        return 0
    except (ValueError, OSError, KeyError, json.JSONDecodeError) as error:
        print("test impact: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
