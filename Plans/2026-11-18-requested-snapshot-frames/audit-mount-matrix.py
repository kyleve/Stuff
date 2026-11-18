#!/usr/bin/env python3
"""Verify both simulator reports against independent checked-in reference inventories."""

import argparse
import base64
from collections import Counter, defaultdict
import hashlib
import json
import math
from pathlib import Path
import struct
import sys

REPO = Path(__file__).resolve().parents[2]
WHERE = "WhereUISnapshotTests"
INSTALLER = "InstallerKitUISnapshotTests"
ROOTS = {
    WHERE: REPO / "Where/WhereUI/SnapshotTests/__Snapshots__",
    INSTALLER: REPO / "Shared/InstallerKitUI/SnapshotTests/__Snapshots__",
}
# CalendarSnapshotCases.detail changes the sizing of these named test subjects to
# intrinsic, retaining their iPhone/iPad identifiers. Its other screens stay full-size.
MONTHS = {
    "FlightAndEvidenceBadges",
    "MonthAccessibility",
    "Flights",
    "Itinerary",
    "ItineraryOverlap",
    "WithData",
    "Empty",
    "FutureWithoutPlans",
    "MissingDays",
    "Focused",
    "FocusedPlannedStay",
    "MultiRegionPlannedStay",
    "PlannedStayHidden",
}
SETTLED_MONTHS = {
    "Itinerary",
    "ItineraryOverlap",
    "FocusedPlannedStay",
    "MultiRegionPlannedStay",
}
# Test method and expected ordinary count. Year's other test methods cover adaptive shells.
SUITES = {
    "FlightStatusBanner": ("flightStatusBanner", 20),
    "TodayWidgetView": ("todayWidget", 8),
    "YearTotalsWidgetView": ("yearTotalsWidget", 6),
    "TodayInlineAccessoryView": ("todayInlineAccessory", 4),
    "TodayCircularAccessoryView": ("todayCircularAccessory", 4),
    "YearTotalsRectangularAccessoryView": ("yearTotalsRectangularAccessory", 4),
    "CalendarContentView": ("calendarContent", 36),
    "YearView": ("year", 4),
    "UpdateFailureCard": ("failure", 6),
}
VERDICTS = (
    "identicalPNG",
    "equalPixels",
    "withinTolerance",
    "differentPixels",
    "differentDimensions",
)
IMMEDIATE = "immediate"
SETTLED = "settledDiagnostic"


def check(condition, message):
    if not condition:
        raise ValueError(message)


def reference_inventory():
    all_refs = set()
    requests = {}
    for family, (method, count) in SUITES.items():
        bundle = INSTALLER if family == "UpdateFailureCard" else WHERE
        folder = ROOTS[bundle] / (family + "SnapshotTests")
        before = len(requests)
        for path in sorted(folder.rglob(f"{method}.*.png")):
            all_refs.add(path)
            identifier = path.stem.removeprefix(method + ".")
            case = identifier.split("_")[0]
            if identifier.endswith("_accessibility"):
                continue
            if family == "CalendarContentView" and case not in MONTHS:
                continue
            if family == "YearView" and case != "ModePicker":
                continue
            settled = family in {"UpdateFailureCard", "YearView"} or (
                family == "CalendarContentView" and case in SETTLED_MONTHS
            )
            requests[path] = (
                family,
                bundle,
                identifier,
                SETTLED if settled else IMMEDIATE,
            )
        check(
            len(requests) - before == count,
            f"{folder}: reference inventory expected {count} images",
        )
    return all_refs, requests


def png_info(path):
    data = path.read_bytes()
    check(
        data[:8] == b"\x89PNG\r\n\x1a\n" and data[12:16] == b"IHDR",
        f"Invalid PNG: {path}",
    )
    width, height = struct.unpack(">II", data[16:24])
    return base64.b64encode(hashlib.sha256(data).digest()).decode(), (width, height)


def verify_verdict(verdict, left, right, label):
    check(verdict in VERDICTS, f"{label}: unknown verdict {verdict!r}")
    check(
        (verdict == "identicalPNG") == (left[0] == right[0]),
        f"{label}: digest disagrees with verdict",
    )
    check(
        (verdict == "differentDimensions") == (left[1] != right[1]),
        f"{label}: dimensions disagree with verdict",
    )


def check_row(row, root, path, family, cohort, pass_name):
    arms = (
        ["production", "native"]
        if cohort == IMMEDIATE
        else ["production", "immediateControl", "native"]
    )
    if cohort == SETTLED and family in {"CalendarContentView", "YearView"}:
        arms.append("settledNative")
    if pass_name == "repeat":
        arms.reverse()
    observations = row["measurements"]
    check(
        [m["backend"] for m in observations] == arms,
        f"{path}: missing or out-of-order measurements",
    )
    check(
        row["suite"] == f"{family}SnapshotTests.swift"
        and row["test"] == SUITES[family][0] + "()",
        f"{path}: wrong suite or test",
    )
    check(
        row["cohort"] == cohort, f"{path}: incorrect readiness cohort {row['cohort']}"
    )
    reference = png_info(path)
    captures = {}
    needs_artifacts = False
    for m in observations:
        arm = m["backend"]
        check(
            math.isfinite(m["seconds"]) and m["seconds"] >= 0,
            f"{path}/{arm}: invalid elapsed time",
        )
        if "error" in m:
            check(
                m["error"] and "againstReference" not in m and "digest" not in m,
                f"{path}/{arm}: mixed capture and error",
            )
            needs_artifacts = True
            continue
        info = m["digest"], (m["width"], m["height"])
        check(
            len(base64.b64decode(m["digest"], validate=True)) == 32
            and min(info[1]) > 0,
            f"{path}/{arm}: invalid PNG metadata",
        )
        verify_verdict(m["againstReference"], info, reference, f"{path}/{arm}")
        captures[arm] = info
        needs_artifacts |= info[0] != reference[0]
    for candidate, arm, key in [
        ("native", "production", "candidateVsProduction"),
        ("native", "immediateControl", "candidateVsImmediateControl"),
        ("settledNative", "production", "settledNativeVsProduction"),
    ]:
        if candidate in captures and arm in captures:
            verify_verdict(
                row.get(key), captures[candidate], captures[arm], f"{path}/{key}"
            )
        else:
            check(
                key not in row,
                f"{path}: claims comparison without both captures: {key}",
            )
    check(
        ("artifacts" in row) == needs_artifacts,
        f"{path}: unexpected or missing difference directory",
    )
    if needs_artifacts:
        folder = (root / row["artifacts"]).resolve()
        check(
            root.resolve() in folder.parents, f"{folder}: not inside this bundle report"
        )
        for name, info in {"reference": reference, **captures}.items():
            check(
                png_info(folder / f"{name}.png") == info,
                f"{path}/{name}: exported PNG differs from reported capture",
            )


def describe(counts):
    return (
        ", ".join(f"{name}={count}" for name, count in sorted(counts.items())) or "none"
    )


def report_group(name, rows):
    times = Counter()
    timed = Counter()
    pairs = 0
    comparisons = defaultdict(Counter)
    for row in rows:
        completed = all("error" not in m for m in row["measurements"])
        pairs += completed
        for m in row["measurements"]:
            arm = m["backend"]
            if completed:
                times[arm] += m["seconds"]
                timed[arm] += 1
            comparisons[f"{arm}/reference"][m.get("againstReference", "error")] += 1
        comparisons["native/production"][row.get("candidateVsProduction", "error")] += 1
        if any(m["backend"] == "settledNative" for m in row["measurements"]):
            comparisons["settledNative/production"][
                row.get("settledNativeVsProduction", "error")
            ] += 1
        if row["cohort"] == SETTLED:
            comparisons["native/immediateControl"][
                row.get("candidateVsImmediateControl", "error")
            ] += 1
    print(
        f"  {name}: {len(rows)} requests, {pairs} complete. Paired render seconds "
        + ", ".join(
            f"{arm}={total:.4f}s/{timed[arm]}" for arm, total in sorted(times.items())
        )
    )
    print(
        "    "
        + "; ".join(
            f"{label} [{describe(counts)}]"
            for label, counts in sorted(comparisons.items())
        )
    )


def audit(output):
    all_refs, expected = reference_inventory()
    passes = {}
    skipped = {}
    failures = []
    for pass_name in ("first", "repeat"):
        rows = {}
        exclusions = {}
        for bundle in ROOTS:
            root = output / pass_name / bundle
            report = json.loads((root / "matrix.json").read_text())
            check(
                report["bundle"] == bundle and report["pass"] == pass_name,
                f"{root}: incorrect report header",
            )
            for row in report["rows"]:
                path = Path(row["reference"])
                if "excluded" in row:
                    check(
                        path in all_refs
                        and path not in expected
                        and path not in exclusions
                        and not row["measurements"],
                        f"{path}: duplicate or incorrectly excluded",
                    )
                    exclusions[path] = row["excluded"]
                    continue
                check(
                    path in expected and path not in rows,
                    f"{path}: unexpected or duplicate measured reference",
                )
                family, wanted_bundle, identifier, cohort = expected[path]
                check(
                    bundle == wanted_bundle and row["identifier"] == identifier,
                    f"{path}: wrong request identity",
                )
                check_row(row, root, path, family, cohort, pass_name)
                rows[path] = row
                for m in row["measurements"]:
                    verdict = m.get("againstReference", "error")
                    if verdict not in VERDICTS[:2]:
                        failures.append(
                            f"{pass_name} {family}/{identifier} {m['backend']}: {verdict} {m.get('error', '')}".rstrip()
                        )
        check(
            set(rows) == set(expected),
            f"{pass_name}: missing references: {sorted(str(p) for p in expected.keys() - rows.keys())}",
        )
        check(
            set(exclusions) == all_refs - set(expected),
            f"{pass_name}: incomplete excluded reference inventory",
        )
        skipped[pass_name] = exclusions
        passes[pass_name] = rows
        print(
            f"{pass_name}: {len(rows)} eligible of {len(all_refs)} reviewed references. Excluded "
            + describe(Counter(exclusions.values()))
        )
        groups = defaultdict(list)
        for path, row in rows.items():
            family, _, _, cohort = expected[path]
            groups[(family, cohort)].append(row)
            groups[("All", cohort)].append(row)
            if any(m["backend"] == "settledNative" for m in row["measurements"]):
                groups[("Retained settling", cohort)].append(row)
            if family != "FlightStatusBanner":
                groups[("New subjects", cohort)].append(row)
        for (name, cohort), selected in sorted(groups.items()):
            report_group(f"{name}/{cohort}", selected)
    check(skipped["first"] == skipped["repeat"], "Exclusions changed between runs")
    changes = Counter()
    for path in expected:

        def digests(pass_name):
            return {
                m["backend"]: m.get("digest")
                for m in passes[pass_name][path]["measurements"]
            }

        first, repeat = digests("first"), digests("repeat")
        for arm in first:
            if not first[arm] or not repeat[arm]:
                changes[f"{arm} unavailable"] += 1
            elif first[arm] == repeat[arm]:
                changes[f"{arm} identical"] += 1
            else:
                changes[f"{arm} changed"] += 1
                print(f"Cross-pass variation: {path.relative_to(REPO)} ({arm})")
    print("Across passes: " + describe(changes))
    if failures:
        print("Differences from reviewed references:")
        print("\n".join(failures))
    else:
        print("All captures matched the reviewed PNG or its exact pixels.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "output",
        type=Path,
        help="run-prototype output directory containing first/ and repeat/",
    )
    args = parser.parse_args()
    try:
        audit(args.output)
    except (OSError, ValueError, KeyError, TypeError, struct.error) as exc:
        sys.exit(f"Incomplete or inconsistent experiment evidence: {exc}")
