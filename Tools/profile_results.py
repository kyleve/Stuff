"""Best-effort build and test hot-spot reports for the public ``./profile``."""

import argparse
from collections import defaultdict
import json
from pathlib import Path
import re
import sys
from typing import Iterable, Mapping, Optional, Sequence

from xcode_results import test_cases


def build_report(log: str, typecheck_threshold: int) -> str:
    phase_pattern = re.compile(r"^(.+?) \((\d+) tasks?\) \| ([\d.]+) seconds$", re.M)
    phases = [
        (match.group(1).strip(), int(match.group(2)), float(match.group(3)))
        for match in phase_pattern.finditer(log)
    ]
    lines: list[str] = []
    if phases:
        total = sum(phase[2] for phase in phases)
        lines.extend(
            [
                "Build phases (summed task-time across cores; wall is lower thanks to",
                "parallelism — use the shares, not the absolute seconds):",
            ]
        )
        for name, count, seconds in sorted(phases, key=lambda phase: -phase[2]):
            share = 100 * seconds / total if total else 0
            lines.append(f"  {seconds:8.2f}s  {share:4.0f}%  {name} ({count})")
    else:
        lines.append("  (no build-timing summary found — was this a no-op incremental build?)")

    typechecks = re.findall(
        r"(/[^:\n]+:\d+:\d+): warning: (.*?took (\d+)ms to type-check.*)$",
        log,
        re.M,
    )
    lines.append("")
    if typechecks:
        lines.append(f"Slow type-check sites (limit {typecheck_threshold}ms):")
        for location, _message, milliseconds in sorted(
            typechecks, key=lambda item: -int(item[2])
        ):
            short = re.sub(r"^.*?/((?:Where|Shared)/)", r"\1", location)
            lines.append(f"  {int(milliseconds):6d}ms  {short}")
    else:
        lines.extend(
            [
                f"Slow type-check sites (limit {typecheck_threshold}ms): none — no expression or",
                "function body exceeded the threshold.",
            ]
        )
    return "\n".join(lines)


def test_report(
    documents: Sequence[Mapping[str, object]],
    *,
    top: int,
    threshold: float,
) -> str:
    cases = []
    for document in documents:
        cases.extend(case for case in test_cases(document) if case.result != "skipped")

    total = sum(case.duration_seconds for case in cases)
    lines = [f"{len(cases)} tests, summed self-time {total:.2f}s", ""]
    lines.append(f"Slowest {top} tests:")
    for case in sorted(cases, key=lambda item: -item.duration_seconds)[:top]:
        flag = "  <== over threshold" if case.duration_seconds >= threshold else ""
        lines.append(
            f"  {case.duration_seconds:7.3f}s  {case.bundle} / {case.name}{flag}"
        )

    by_bundle: dict[str, list[float]] = defaultdict(lambda: [0.0, 0])
    for case in cases:
        by_bundle[case.bundle][0] += case.duration_seconds
        by_bundle[case.bundle][1] += 1
    lines.extend(["", "Per-bundle self-time:"])
    for bundle, (duration, count) in sorted(
        by_bundle.items(), key=lambda item: -item[1][0]
    ):
        lines.append(f"  {duration:7.3f}s  {bundle} ({int(count)} tests)")

    over = [case for case in cases if case.duration_seconds >= threshold]
    lines.append("")
    if over:
        lines.append(
            f"{len(over)} test(s) at/over the {threshold}s threshold (flagged above)."
        )
    else:
        lines.append(f"No tests at/over the {threshold}s threshold.")
    return "\n".join(lines)


def main(arguments: Optional[Iterable[str]] = None) -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    build = subparsers.add_parser("build")
    build.add_argument("--log", required=True, type=Path)
    build.add_argument("--typecheck-threshold", required=True, type=int)

    tests = subparsers.add_parser("tests")
    tests.add_argument("--tests-json", action="append", type=Path, default=[])
    tests.add_argument("--tests-json-paths")
    tests.add_argument("--top", required=True, type=int)
    tests.add_argument("--threshold", required=True, type=float)

    options = parser.parse_args(arguments)
    try:
        if options.command == "build":
            print(
                build_report(
                    options.log.read_text(errors="replace"),
                    options.typecheck_threshold,
                )
            )
        elif options.command == "tests":
            paths = list(options.tests_json)
            if options.tests_json_paths:
                paths.extend(Path(path) for path in options.tests_json_paths.split(":"))
            if not paths:
                parser.error("tests requires --tests-json or --tests-json-paths")
            documents = []
            for path in paths:
                with path.open() as stream:
                    documents.append(json.load(stream))
            print(test_report(documents, top=options.top, threshold=options.threshold))
    except Exception as error:  # reporting must not abort the profiled run
        if options.command == "build":
            source = options.log
            kind = "build timing"
        else:
            source = options.tests_json_paths or ":".join(
                str(path) for path in options.tests_json
            )
            kind = "test results"
        print(f"warning: couldn't parse {kind} from {source} ({error})", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
