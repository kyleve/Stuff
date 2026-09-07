"""Render the snapshot timing and difference reports used by root commands."""

import argparse
from collections import Counter
import json
from pathlib import Path
from typing import Iterable, Mapping, Optional, Sequence


def load_json_lines(path: Path) -> list[dict]:
    with path.open() as stream:
        return [json.loads(line) for line in stream if line.strip()]


def timing_report(
    rows: Sequence[Mapping[str, object]],
    *,
    detailed: bool,
    empty_message: str,
) -> str:
    if not rows:
        return f"  ({empty_message})"

    grand = sum(float(row["total"]) for row in rows)
    phases: Counter[str] = Counter()
    for row in rows:
        phases.update(row["phases"])

    lines = [
        f"  {len(rows)} captures, {grand:.1f}s total, "
        f"{grand / len(rows):.3f}s per image",
        "",
        f"  {'phase':20s} {'total':>9s} {'share':>7s} {'mean':>9s}",
    ]
    for phase, seconds in phases.most_common():
        share = 100 * seconds / grand if grand else 0
        lines.append(
            f"  {phase:20s} {seconds:8.2f}s {share:6.1f}% "
            f"{seconds / len(rows):8.3f}s"
        )

    if detailed:
        _append_counts(lines, rows, "sizing", "sizing")
        _append_counts(
            lines,
            rows,
            "measurement readiness",
            "measurementReadiness",
        )
        _append_counts(lines, rows, "capture settle", "captureSettle")
        lines.extend(["", "  intrinsic measurement by readiness:"])
        readiness_values = sorted(
            {str(row.get("measurementReadiness", "unknown")) for row in rows}
        )
        for readiness in readiness_values:
            selected = [
                row
                for row in rows
                if str(row.get("measurementReadiness", "unknown")) == readiness
            ]
            seconds = sum(
                float(row["phases"].get("intrinsicMeasure", 0)) for row in selected
            )
            lines.append(
                f"    {seconds:8.2f}s  {readiness} ({len(selected)} captures)"
            )

    passes = [int(row["settlePasses"]) for row in rows]
    lines.extend(
        [
            "",
            f"  settle passes: min {min(passes)}, max {max(passes)}, "
            f"mean {sum(passes) / len(passes):.1f}",
            "",
            "  slowest captures:",
        ]
    )
    for row in sorted(rows, key=lambda item: -float(item["total"]))[:8]:
        lines.append(f"    {float(row['total']):6.3f}s  {row['id']}")
    return "\n".join(lines)


def difference_report(
    rows: Sequence[Mapping[str, object]],
    *,
    is_recording: bool,
) -> str:
    visible = list(rows)
    if is_recording:
        visible = [row for row in visible if row["outcome"] != "referenceMissing"]
    if not visible:
        return "  Every capture matched its reference byte for byte."

    differs = [row for row in visible if row["outcome"] == "differs"]
    lines = [f"  {len(visible)} capture(s) did not match byte for byte.", ""]
    if differs:
        lines.append(
            f"  {'maxDelta':>8s} {'pixels':>8s} {'of image':>9s}  "
            "region (x,y,w,h)  reference"
        )
        for row in sorted(differs, key=lambda item: -int(item["maxChannelDelta"])):
            region = ",".join(str(value) for value in row["region"])
            reference = str(row.get("reference", "?")).split("__Snapshots__/")[-1]
            lines.append(
                f"  {int(row['maxChannelDelta']):8d} "
                f"{int(row['differingPixels']):8d} "
                f"{100 * float(row['differingFraction']):8.3f}%  "
                f"({region})  {reference}"
            )
        lines.extend(
            [
                "",
                "  A single-digit max delta is sub-visible drift; a large one is a real",
                "  change however few pixels it touches.",
            ]
        )
    for row in visible:
        if row["outcome"] != "differs":
            lines.append(
                f"  {row['outcome']}: {row.get('reference') or row.get('detail')}"
            )
    return "\n".join(lines)


def _append_counts(
    lines: list[str],
    rows: Sequence[Mapping[str, object]],
    title: str,
    key: str,
) -> None:
    counts = Counter(str(row.get(key, "unknown")) for row in rows)
    lines.extend(["", f"  {title}:"])
    for value, count in sorted(counts.items(), key=lambda item: (-item[1], item[0])):
        lines.append(f"    {count:4d}  {value}")


def main(arguments: Optional[Iterable[str]] = None) -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    timings = subparsers.add_parser("timings")
    timings.add_argument("path", type=Path)
    timings.add_argument("--detailed", action="store_true")
    timings.add_argument(
        "--empty-message",
        default="no timing lines — was this a snapshot scheme?",
    )

    differences = subparsers.add_parser("differences")
    differences.add_argument("path", type=Path)
    differences.add_argument("--recording", action="store_true")

    options = parser.parse_args(arguments)
    rows = load_json_lines(options.path)
    if options.command == "timings":
        print(
            timing_report(
                rows,
                detailed=options.detailed,
                empty_message=options.empty_message,
            )
        )
    elif options.command == "differences":
        print(difference_report(rows, is_recording=options.recording))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
