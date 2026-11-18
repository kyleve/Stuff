#!/usr/bin/env python3
"""Audit the frozen same-mount trial against the references, timing rows and other arms."""

import argparse
from collections import Counter
from functools import cache
import hashlib
import json
from math import isfinite
from pathlib import Path
import runpy
import struct
import subprocess
import sys
import uuid
import xml.etree.ElementTree as ET


PLAN = Path(__file__).resolve().parent
REPO = PLAN.parents[1]
ORDER = {
    "first": ["baseline", "retained", "early"],
    "reverse": ["early", "retained", "baseline"],
}


def check(condition, detail):
    if not condition:
        raise ValueError(detail)


def selected():
    lines = (PLAN / "mount-200.txt").read_text().splitlines()
    paths = [
        line.strip() for line in lines if line.strip() and not line.startswith("#")
    ]
    check(len(paths) == len(set(paths)) == 200, "Expected 200 unique manifest entries")
    old = runpy.run_path(str(PLAN / "audit-mount-matrix.py"))["reference_inventory"]()[
        1
    ]
    tracked = set(
        subprocess.check_output(
            ["git", "-C", REPO, "ls-files", "--", "*__Snapshots__/*.png"], text=True
        ).splitlines()
    )
    for name in paths:
        path = Path(name)
        check(
            not path.is_absolute()
            and path.as_posix() == name
            and ".." not in path.parts
            and "__Snapshots__" in path.parts
            and path.suffix == ".png"
            and name in tracked
            and (REPO / path).is_file()
            and (REPO / path) not in old
            and not path.stem.endswith("_accessibility"),
            f"Invalid or previously tested reference: {name}",
        )
    return paths


@cache
def png(path):
    with path.open("rb") as f:
        header = f.read(24)
        check(
            header[:8] == b"\x89PNG\r\n\x1a\n" and header[12:16] == b"IHDR",
            f"Bad PNG: {path}",
        )
        digest = hashlib.sha256(header)
        for data in iter(lambda: f.read(256 * 1024), b""):
            digest.update(data)
    return (*struct.unpack(">II", header[16:24]), digest.hexdigest())


@cache
def panels(name):
    # Layout metadata is part of the reference identity. Read real panel names
    # from the sheet instead of assuming every sheet contains two themes.
    if "themes" not in Path(name).parts:
        return ()
    with (REPO / name).open("rb") as f:
        f.read(8)
        while chunk := f.read(8):
            length, tag = struct.unpack(">I4s", chunk)
            if tag != b"iTXt":
                f.seek(length + 4, 1)
                continue
            payload = f.read(length)
            f.read(4)
            if not payload.startswith(b"XML:com.adobe.xmp\x00"):
                continue
            xmp = ET.fromstring(payload[payload.index(b"<") :])
            for node in xmp.iter():
                if node.text and node.text.lstrip().startswith("{"):
                    layout = json.loads(node.text).get("layout", {})
                    if "panels" in layout:
                        ids = tuple(panel["identity"] for panel in layout["panels"])
                        check(
                            ids and len(ids) == len(set(ids)),
                            f"Malformed panel map: {name}",
                        )
                        return ids
    raise ValueError(f"Missing panel map: {name}")


def load_timings(root):
    counts = {}
    for line in (root / "test/timings.jsonl").read_text().splitlines():
        row = json.loads(line)
        identifier = str(uuid.UUID(row["captureID"]))
        check(identifier not in counts, f"{root}: duplicate timing UUID {identifier}")
        counts[identifier] = row
    return counts


def incomplete_inventory(root, suffix, missing, extra):
    issues = []
    for log in (root / "test").glob("*.log"):
        with log.open(errors="replace") as lines:
            issues.extend(
                line.strip()
                for line in lines
                if "recorded an issue" in line
                or ("✘ Test" in line and "failed after" in line)
            )
    diagnosis = (
        "Swift test failures: " + " | ".join(dict.fromkeys(issues))[:1800]
        if issues
        else "No Swift test failure found in the available logs."
    )
    return (
        f"{root}: incomplete {suffix} inventory; missing {sorted(missing)}, "
        f"extra {sorted(extra)}. {diagnosis}"
    )


def check_arm(root, arm, names):
    artifacts = root / "images"
    expected = set(names)
    for suffix in [".png", ".json"]:
        actual = {
            p.relative_to(artifacts).with_suffix(".png").as_posix()
            for p in artifacts.rglob("*" + suffix)
        }
        if expected != actual:
            raise ValueError(
                incomplete_inventory(root, suffix, expected - actual, actual - expected)
            )
    timings = load_timings(root)
    seen = set()
    results = {}
    for name in names:
        location = artifacts / name
        obs = json.loads(location.with_suffix(".json").read_text())
        width, height, digest = png(location)
        check(
            obs["reference"] == name
            and obs["arm"] == arm
            and (width, height) == (obs["width"], obs["height"])
            and type(obs["accepted"]) is bool
            and obs["accepted"] == (not obs.get("detail"))
            and isfinite(obs["seconds"])
            and obs["seconds"] > 0,
            f"{root}: inconsistent export for {name}",
        )
        ids = panels(name)
        check(obs["panels"] == len(ids), f"{name}: unexpected panel count")
        identifier = Path(name).stem.split(".", 1)[1]
        expected_captures = [f"{identifier}/{panel}" for panel in ids] or [identifier]
        captures = obs["captures"]
        check(
            [c["name"] for c in captures] == expected_captures,
            f"{name}: capture names or panel order differ",
        )
        timing_data = []
        for capture in captures:
            identity = str(uuid.UUID(capture["id"]))
            check(
                identity in timings and identity not in seen,
                f"{name}: missing or reused timing {identity}",
            )
            seen.add(identity)
            row = timings[identity]
            mounts = row["wrapperMounts"]
            mode = row["mountPath"]
            early = row["earlyContent"]
            check(
                row["id"] == capture["name"]
                and mounts == capture["wrapperMounts"]
                and mode == capture["mountPath"]
                and mode == ("remounted" if arm == "baseline" else "retained")
                and type(mounts) is int
                and mounts == (2 if arm == "baseline" else 1)
                and row["sizing"] in ("intrinsic", "fullContent2D")
                and type(early) is bool
                and early == capture["earlyContent"]
                and early
                == (
                    arm == "early"
                    and row["captureSettle"] == "settled"
                    and "preparationHook" not in row["phases"]
                    and "hook" not in row["phases"]
                )
                and isfinite(row["total"])
                and row["total"] >= 0,
                f"{name}: incorrect capture path, mount count or readiness for {row['id']}: {row}",
            )
            timing_data.append(row)
        results[name] = {
            "seconds": obs["seconds"],
            "accepted": obs["accepted"],
            "detail": obs.get("detail"),
            "width": width,
            "height": height,
            "digest": digest,
            "captures": timing_data,
        }
    check(
        seen == set(timings), f"{root}: {len(set(timings) - seen)} orphan timing rows"
    )
    return results


def compare(executable, left, right, comparisons):
    width, height, left_hash = png(left)
    right_width, right_height, right_hash = png(right)
    key = left_hash, right_hash
    if key not in comparisons:
        if left_hash == right_hash:
            result = {
                "kind": "bytes",
                "width": width,
                "height": height,
                "rightWidth": right_width,
                "rightHeight": right_height,
                "changed": 0,
                "alpha": 0,
                "max": 0,
                "over8": 0,
            }
        else:
            cmd = subprocess.run(
                [executable, left, right], check=True, capture_output=True, text=True
            )
            result = json.loads(cmd.stdout)
        check(
            result["kind"] in ("bytes", "pixels", "size", "changed")
            and (
                result["width"],
                result["height"],
                result["rightWidth"],
                result["rightHeight"],
            )
            == (width, height, right_width, right_height)
            and (result["kind"] == "size")
            == ((width, height) != (right_width, right_height))
            and (result["kind"] == "bytes") == (left_hash == right_hash),
            f"Inconsistent pixel verdict for {left} and {right}: {result}",
        )
        if result["kind"] != "size":
            check(
                0 <= result["alpha"] <= result["changed"] <= width * height
                and 0 <= result["over8"] <= result["changed"]
                and 0 <= result["max"] <= 255
                and (result["kind"] == "changed") == (result["changed"] > 0),
                f"Invalid pixel counts for {left} and {right}",
            )
        comparisons[key] = result
    return comparisons[key]


def pair_stats(values):
    counts = Counter(d["kind"] for d in values)
    counts["over8Images"] = sum(
        d.get("over8", 0) > 0 for d in values if d["kind"] != "size"
    )
    return dict(counts)


def render_count(items, key):
    return sum(c[key] for obs in items for c in obs["captures"])


def groups_for_pass(images, pass_name):
    # A height change can reduce the work in a capture. Report timing for a
    # constant-geometry subset as well as the complete work and ordinary verdict.
    groups = {}
    for name, image in images.items():
        arms = image["runs"][pass_name]
        parts = Path(name).parts
        family = parts[parts.index("__Snapshots__") + 1].removesuffix("SnapshotTests")
        sizes = {(row["width"], row["height"]) for row in arms.values()}
        labels = [
            "all",
            "suite/" + family,
            "shape/sheets" if panels(name) else "shape/singles",
            "readiness/early"
            if any(c["earlyContent"] for c in arms["early"]["captures"])
            else "readiness/unchanged",
        ]
        if len(sizes) == 1:
            labels.append("geometry/all-arms-same-size")
        for label in labels:
            group = groups.setdefault(
                label, {"images": 0, "seconds": Counter(), "accepted": Counter()}
            )
            group["images"] += 1
            for key, obs in arms.items():
                group["seconds"][key] += obs["seconds"]
                group["accepted"][key] += obs["accepted"]
    return groups


def audit(args):
    names = selected()
    passes = [args.pass_name] if args.pass_name else list(ORDER)
    if args.check_arm:
        pass_name, arm = args.check_arm
        check(pass_name in ORDER and arm in ORDER[pass_name], "Unknown pass or arm")
        one = check_arm(args.run / pass_name / arm, arm, names)
        print(
            f"{pass_name}/{arm}: {len(one)} exports, {sum(len(v['captures']) for v in one.values())} verified timings"
        )
        return
    eras = [f"{p} {a}" for p in passes for a in ORDER[p]]
    order = args.run / "order.txt"
    if len(passes) == 2:
        check(order.is_file(), f"{order}: the complete six-arm run order is missing")
    if order.is_file():
        executed = [
            line
            for line in order.read_text().splitlines()
            if line and (len(passes) == 2 or line.split()[0] in passes)
        ]
        check(
            executed == eras, f"Arm order mismatch: expected {eras}, found {executed}"
        )
    summary = {name: {"runs": {}, "comparisons": {}} for name in names}
    diffs = {}
    totals = {}
    seen_uuids = set()
    arm_pairs = {
        "retainedVsBaseline": ("baseline", "retained"),
        "earlyVsBaseline": ("baseline", "early"),
        "earlyVsRetained": ("retained", "early"),
    }
    for p in passes:
        totals[p] = {}
        for a in ORDER[p]:
            root = args.run / p / a
            records = check_arm(root, a, names)
            for name, row in records.items():
                summary[name]["runs"].setdefault(p, {})[a] = row
                label = f"{p}.{a}VsReference"
                summary[name]["comparisons"][label] = compare(
                    args.pixels, REPO / name, root / "images" / name, diffs
                )
            group = list(records.values())
            uuids = {
                uuid.UUID(c["captureID"]) for row in group for c in row["captures"]
            }
            check(
                not seen_uuids.intersection(uuids),
                f"{root}: capture UUID repeated across independent runs",
            )
            seen_uuids.update(uuids)
            phases = Counter()
            for obs in group:
                for capture in obs["captures"]:
                    phases.update(capture["phases"])
            totals[p][a] = {
                "seconds": sum(r["seconds"] for r in group),
                "accepted": sum(r["accepted"] for r in group),
                "captures": sum(len(r["captures"]) for r in group),
                "wrapperMounts": render_count(group, "wrapperMounts"),
                "earlyContent": render_count(group, "earlyContent"),
                "settleCalls": render_count(group, "settleCalls"),
                "settlePasses": render_count(group, "settlePasses"),
                "phaseSeconds": {
                    key: round(value, 3) for key, value in sorted(phases.items())
                },
            }
            print(f"{p}/{a}: {totals[p][a]}", flush=True)
            totals[p][a]["vsReference"] = pair_stats(
                [summary[name]["comparisons"][f"{p}.{a}VsReference"] for name in names]
            )
        for label, (left, right) in arm_pairs.items():
            key = f"{p}.{label}"
            for name in names:
                summary[name]["comparisons"][key] = compare(
                    args.pixels,
                    args.run / p / left / "images" / name,
                    args.run / p / right / "images" / name,
                    diffs,
                )
            print(
                f"{key}: {pair_stats([s['comparisons'][key] for s in summary.values()])}",
                flush=True,
            )
    if len(passes) == 2:
        for arm in ORDER["first"]:
            key = f"{arm}.repeat"
            for name in names:
                summary[name]["comparisons"][key] = compare(
                    args.pixels,
                    args.run / "first" / arm / "images" / name,
                    args.run / "reverse" / arm / "images" / name,
                    diffs,
                )
            print(
                f"{key}: {pair_stats([s['comparisons'][key] for s in summary.values()])}",
                flush=True,
            )
    # Require the same fixtures and declared readiness in each arm and order, so
    # a speed difference cannot come from measuring a different panel.
    for name, image in summary.items():
        runs = [r for pass_runs in image["runs"].values() for r in pass_runs.values()]
        for row in runs[1:]:
            check(
                len(row["captures"]) == len(runs[0]["captures"]),
                f"{name}: capture count changed",
            )
            for first, other in zip(runs[0]["captures"], row["captures"]):
                for k in ("id", "sizing", "measurementReadiness", "captureSettle"):
                    check(first[k] == other[k], f"{name}: {k} differed between arms")
        if len(passes) == 2:
            first_early = image["runs"]["first"]["early"]["captures"]
            reverse_early = image["runs"]["reverse"]["early"]["captures"]
            check(
                [c["earlyContent"] for c in first_early]
                == [c["earlyContent"] for c in reverse_early],
                f"{name}: early-content eligibility changed between processes",
            )
    if len(passes) == 2:
        check(
            all(totals[p]["early"]["earlyContent"] > 0 for p in passes),
            "Early arm never exercised its early content path",
        )
    destination = args.run / (
        "summary-200.json" if len(passes) == 2 else f"summary-200-{passes[0]}.json"
    )
    groups = {p: groups_for_pass(summary, p) for p in passes}
    destination.write_text(
        json.dumps({"totals": totals, "groups": groups, "images": summary}, indent=2)
        + "\n"
    )
    print(f"Verified {len(names)} references; wrote {destination}.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run", type=Path)
    parser.add_argument(
        "pixels", type=Path, help="Path to compiled pixel-comparison executable"
    )
    parser.add_argument("--pass", dest="pass_name", choices=ORDER)
    parser.add_argument(
        "--check-arm",
        nargs=2,
        metavar=("PASS", "ARM"),
        help="Validate one arm's exports, manifest and timings without pair comparisons",
    )
    args = parser.parse_args()
    try:
        audit(args)
    except (
        OSError,
        ValueError,
        KeyError,
        TypeError,
        subprocess.CalledProcessError,
        ET.ParseError,
        struct.error,
    ) as e:
        sys.exit(f"Invalid or incomplete experiment evidence: {e}")
