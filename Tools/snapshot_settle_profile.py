"""Validate and summarize observational settling traces from hosted test logs."""

import argparse
from collections import Counter, defaultdict
import json
import math
from pathlib import Path
import re
import sys
from typing import Optional, Sequence
from uuid import UUID


TRACE = "SNAPSHOT_SETTLE_TRACE "
TIMING = "SNAPSHOT_TIMING "
OPERATIONS = ("sleepActual", "layout", "render", "pixelCheck")
REASONS = {
    "measurement",
    "content",
    "nativeInsets",
    "postAction",
    "scrollReset",
    "accessibilityPreparation",
    "standalone",
}
OUTCOMES = {"settled", "skipped", "timedOut", "starved", "cancelled"}
EVENTS = {None, "anchor", "matching", "changed", "missing"}


def nonnegative(value: object, label: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"{label} must be a number")
    if not math.isfinite(value) or value < 0:
        raise ValueError(f"{label} must be finite and nonnegative")
    return float(value)


def integer(value: object, label: str, minimum: int = 0) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < minimum:
        raise ValueError(f"{label} must be an integer >= {minimum}")
    return value


def identity(row: dict) -> str:
    value = row.get("captureID")
    if not isinstance(value, str):
        raise ValueError("missing captureID; use a run with settling tracing enabled")
    UUID(value)
    if not isinstance(row.get("id"), str):
        raise ValueError("missing capture label")
    return value


def validate_trace(row: dict) -> None:
    identity(row)
    if integer(row.get("version"), "version", 1) != 1:
        raise ValueError("unsupported settling trace version")
    integer(row.get("ordinal"), "ordinal", 1)
    if row.get("reason") not in REASONS or row.get("outcome") not in OUTCOMES:
        raise ValueError("unknown trace reason or outcome")
    if row.get("mechanism") not in {"pixel", "quiescence", "both"}:
        raise ValueError("unknown settling mechanism")
    for key in (
        "captureOffset",
        "minimumDuration",
        "maximumDuration",
        "quietDuration",
        "elapsed",
        "interruptedSleep",
    ):
        nonnegative(row.get(key), key)
    passes = row.get("passes")
    if not isinstance(passes, list):
        raise ValueError("trace passes must be a list")
    previous = 0.0
    for index, sample in enumerate(passes, 1):
        if integer(sample.get("index"), "pass index", 1) != index:
            raise ValueError("pass indices must be contiguous")
        at = nonnegative(sample.get("sampleAt"), "sampleAt")
        if at < previous or at > row["elapsed"]:
            raise ValueError("pass sample time lies outside the ordered phase timeline")
        previous = at
        for key in (*OPERATIONS, "sleepRequested"):
            nonnegative(sample.get(key), key)
        if sample.get("event") not in EVENTS:
            raise ValueError("unknown pixel event")
        for key in ("stable", "floorMet"):
            if not isinstance(sample.get(key), bool):
                raise ValueError(f"{key} must be a boolean")
        if sample.get("pixelStable") is not None and not isinstance(
            sample["pixelStable"], bool
        ):
            raise ValueError("pixelStable must be a boolean when present")
        if row["mechanism"] in {"pixel", "both"} and (
            sample.get("event") is None or sample.get("pixelStable") is None
        ):
            raise ValueError(
                "pixel settling requires pixel event and stability observations"
            )
        if row["mechanism"] == "quiescence" and (
            sample.get("event") is not None or sample.get("pixelStable") is not None
        ):
            raise ValueError(
                "quiescence-only settling cannot report pixel observations"
            )
    accounted = sum(sum(sample[key] for key in OPERATIONS) for sample in passes)
    accounted += row["interruptedSleep"]
    if accounted > row["elapsed"] + 0.001:
        raise ValueError("nonoverlapping operation durations exceed elapsed time")
    if row["outcome"] == "skipped" and passes:
        raise ValueError("skipped settling cannot contain pixel passes")
    if row["outcome"] == "settled" and (
        not passes or not passes[-1]["stable"] or not passes[-1]["floorMet"]
    ):
        raise ValueError("settled outcome lacks a final stability and floor proof")


def parse_logs(paths: Sequence[Path]) -> tuple[list[dict], list[dict], list[dict]]:
    traces, captures, runs = [], [], []
    for path in paths:
        suite = "unknown"
        succeeded = False
        for number, line in enumerate(path.read_text(errors="replace").splitlines(), 1):
            if line.strip() in {"** TEST EXECUTE SUCCEEDED **", "** TEST SUCCEEDED **"}:
                succeeded = True
            elif line.strip() in {"** TEST EXECUTE FAILED **", "** TEST FAILED **"}:
                succeeded = False
            match = re.search(r"◇ Suite (.+) started\.", line)
            if match:
                suite = match.group(1)
            if "SNAPSHOT_SETTLE_TRACE_ERROR" in line:
                raise ValueError(f"{path}:{number}: trace encoding failed")
            prefix = TRACE if TRACE in line else TIMING if TIMING in line else None
            if prefix is None:
                continue
            # Appended observations require their own terminal success marker.
            succeeded = False
            try:
                row = json.loads(line.split(prefix, 1)[1])
                if not isinstance(row, dict):
                    raise ValueError("diagnostic record must be an object")
                identity(row)
                if prefix == TRACE:
                    validate_trace(row)
                else:
                    integer(row.get("settleCalls"), "settleCalls")
                    integer(row.get("settlePasses"), "settlePasses")
            except (ValueError, TypeError, AttributeError) as error:
                raise ValueError(f"{path}:{number}: {error}") from error
            row = {**row, "suite": suite, "sourceLog": str(path)}
            (traces if prefix == TRACE else captures).append(row)
        runs.append({"sourceLog": str(path), "succeeded": succeeded})
    return traces, captures, runs


def distribution(values: list[float]) -> dict:
    ordered = sorted(values)
    if not ordered:
        return {"median": None, "p95": None, "max": None}
    middle = len(ordered) // 2
    median = (
        ordered[middle]
        if len(ordered) % 2
        else sum(ordered[middle - 1 : middle + 1]) / 2
    )
    return {
        "median": median,
        "p95": ordered[math.ceil(len(ordered) * 0.95) - 1],
        "max": ordered[-1],
    }


def summarize_group(rows: list[dict]) -> dict:
    elapsed = sum(row["elapsed"] for row in rows)
    passes = [sample for row in rows for sample in row["passes"]]
    operations = {key: sum(sample[key] for sample in passes) for key in OPERATIONS}
    interrupted = sum(row["interruptedSleep"] for row in rows)
    return {
        "calls": len(rows),
        "passes": len(passes),
        "elapsed": elapsed,
        "operations": operations,
        "interruptedSleep": interrupted,
        "unattributed": max(0, elapsed - sum(operations.values()) - interrupted),
        "outcomes": dict(Counter(row["outcome"] for row in rows)),
        "pixelEvents": dict(
            Counter(sample.get("event") or "notSampled" for sample in passes)
        ),
        "callsWithoutObservedChanges": sum(
            row["mechanism"] in {"pixel", "both"}
            and bool(row["passes"])
            and all(
                sample.get("event") not in {"changed", "missing"}
                for sample in row["passes"]
            )
            for row in rows
        ),
        "quiescenceCalls": sum(row["mechanism"] == "quiescence" for row in rows),
        "callsStableBeforeFloor": sum(
            any(sample["stable"] and not sample["floorMet"] for sample in row["passes"])
            for row in rows
        ),
        "samplesBlockedOnlyByFloor": sum(
            sample["stable"] and not sample["floorMet"] for sample in passes
        ),
        "samplesBlockedOnlyByProof": sum(
            not sample["stable"] and sample["floorMet"] for sample in passes
        ),
        "samplesBlockedByBoth": sum(
            not sample["stable"] and not sample["floorMet"] for sample in passes
        ),
        "elapsedDistribution": distribution([row["elapsed"] for row in rows]),
        "renderDistribution": distribution([sample["render"] for sample in passes]),
        "sleepOvershoot": sum(
            max(0, sample["sleepActual"] - sample["sleepRequested"])
            for sample in passes
        ),
    }


def summarize(
    traces: list[dict], captures: list[dict], runs: Sequence[dict] = ()
) -> dict:
    if not traces:
        raise ValueError("no settling traces found")
    calls = defaultdict(dict)
    for row in traces:
        validate_trace(row)
        owner = calls[identity(row)]
        if row["ordinal"] in owner:
            raise ValueError("duplicate trace call identity")
        owner[row["ordinal"]] = row
    capture_ids = set()
    incomplete = []
    for capture in captures:
        key = identity(capture)
        if key in capture_ids:
            raise ValueError("duplicate capture summary identity")
        capture_ids.add(key)
        rows = calls.get(key, {})
        expected_calls = integer(capture.get("settleCalls"), "settleCalls")
        expected_passes = integer(capture.get("settlePasses"), "settlePasses")
        if (
            set(rows) != set(range(1, expected_calls + 1))
            or sum(len(row["passes"]) for row in rows.values()) != expected_passes
            or any(row["id"] != capture["id"] for row in rows.values())
        ):
            incomplete.append(
                {
                    "captureID": key,
                    "id": capture["id"],
                    "expectedCalls": expected_calls,
                    "foundCalls": len(rows),
                    "expectedPasses": expected_passes,
                    "foundPasses": sum(len(row["passes"]) for row in rows.values()),
                }
            )
    orphaned = sorted(set(calls) - capture_ids)
    grouped = {}
    for field in ("reason", "suite"):
        groups = defaultdict(list)
        for row in traces:
            groups[row.get(field, "unknown")].append(row)
        grouped[field] = {
            name: summarize_group(rows) for name, rows in sorted(groups.items())
        }
    reconciled = bool(captures) and not incomplete and not orphaned
    return {
        "version": 1,
        "complete": reconciled and bool(runs) and all(run["succeeded"] for run in runs),
        "reconciled": reconciled,
        "runs": list(runs),
        "captures": len(captures),
        "tracedOwners": len(calls),
        "incompleteCaptures": incomplete,
        "orphanedOwners": orphaned,
        "total": summarize_group(traces),
        "groups": grouped,
        "slowestCalls": sorted(traces, key=lambda row: -row["elapsed"])[:20],
        "limits": [
            "Operation times are wall time. Suspensions can contain application work and scheduling delay.",
            "Floor and proof flags are overlapping sampled conditions, not additive duration buckets or savings.",
            "No observed low-resolution change does not establish final content readiness.",
            "Suite labels follow serial log order; capture IDs and call ordinals own reconciliation.",
            "Raw records retain failed, cancelled, orphaned and incomplete calls.",
            "Completion requires reconciliation and terminal Xcode success in every input log; selected-suite coverage is external.",
        ],
    }


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("logs", type=Path, nargs="+")
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--require-complete", action="store_true")
    args = parser.parse_args(argv)
    try:
        traces, captures, runs = parse_logs(args.logs)
        report = summarize(traces, captures, runs)
        args.output_dir.mkdir(parents=True, exist_ok=True)
        for name, rows in (("traces", traces), ("captures", captures)):
            (args.output_dir / f"{name}.jsonl").write_text(
                "".join(json.dumps(row, sort_keys=True) + "\n" for row in rows)
            )
        (args.output_dir / "summary.json").write_text(
            json.dumps(report, indent=2, sort_keys=True) + "\n"
        )
        print(
            f"Settling traces: {len(traces)} calls, {report['total']['passes']} passes, "
            f"{len(captures)} captures; complete={report['complete']}"
        )
        for name, row in sorted(
            report["groups"]["reason"].items(), key=lambda item: -item[1]["elapsed"]
        ):
            print(
                f"  {name}: {row['elapsed']:.3f}s, {row['calls']} calls; "
                f"sleep {row['operations']['sleepActual']:.3f}s, "
                f"render {row['operations']['render']:.3f}s, "
                f"pixel check {row['operations']['pixelCheck']:.3f}s"
            )
        return 1 if args.require_complete and not report["complete"] else 0
    except (ValueError, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
