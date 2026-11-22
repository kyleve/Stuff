"""Structured scope and reporting support for the public ``./test`` command."""

import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
import time
from typing import Callable, Iterable, Mapping, Optional, Sequence, TextIO

from grouped_tests import GROUPED_BUNDLE, GroupedTestSuites
from xcode_results import test_cases
from repository import repository_root
from test_selection import (
    Graph,
    describe,
    repository_selection,
)


def snapshot_bundles(project_text: str) -> list[str]:
    return sorted(set(re.findall(r'name:\s*"(\w+SnapshotTests)"', project_text)))


def affected_bundles(
    changed: Sequence[str],
    package: Mapping[str, object],
    project_text: str,
) -> list[str]:
    """Compatibility entry point for callers with an explicit changed-path list."""
    if not changed:
        return []
    return Graph.read(package, project_text).select(list(changed))["selected"]


def grouped_filters(identifiers: Iterable[str], suites: GroupedTestSuites) -> list[str]:
    """Translate logical module selectors for a grouped build without widening coverage."""
    selected = []
    for identifier in identifiers:
        bundle, separator, test = identifier.partition("/")
        if bundle not in suites.bundles:
            selected.append(identifier)
        elif separator:
            suite = test.partition("/")[0]
            if suites.owners.get(suite.partition(".")[0]) != bundle:
                raise ValueError(f"{bundle} has no grouped test suite named {suite!r}")
            selected.append(f"{GROUPED_BUNDLE}/{test}")
        else:
            names = sorted(
                name for name, owner in suites.owners.items() if owner == bundle
            )
            if not names:
                raise ValueError(f"{bundle} has no grouped test suites")
            selected.extend(f"{GROUPED_BUNDLE}/{name}" for name in names)
    return list(dict.fromkeys(selected))


def failure_report(
    document: Mapping[str, object],
    result_path: str,
    project: Path = Path("Project.swift"),
    manifest: Optional[Path] = None,
) -> str:
    failures = [case for case in test_cases(document) if case.result == "failed"]
    owners = {}
    if any(case.bundle == GROUPED_BUNDLE for case in failures):
        try:
            owners = GroupedTestSuites.from_manifest_or_repository(
                project.resolve().parent, manifest
            ).owners
        except (OSError, ValueError, subprocess.CalledProcessError) as error:
            print(
                f"warning: could not resolve original test modules: {error}",
                file=sys.stderr,
            )
    lines: list[str] = []
    for case in failures:
        display = case.display_identifier
        rerun = case.suite_identifier
        if case.bundle == GROUPED_BUNDLE:
            relative = case.only_testing_identifier.removeprefix(GROUPED_BUNDLE + "/")
            suite_path = relative.rpartition("/")[0] or relative
            outer_suite = suite_path.partition("/")[0].partition(".")[0]
            owner = owners.get(outer_suite, GROUPED_BUNDLE)
            display = (
                f"{owner}/{case.suite_name}/{case.name}"
                if case.suites
                else f"{owner}/{case.name}"
            )
            rerun = f"{owner}/{suite_path}"
        lines.append(f"  {display}")
        lines.append(f"      ./test --only '{rerun}'")
    if failures:
        lines.extend(["", f"  Result bundle: {result_path}"])
    return "\n".join(lines)


class ProgressReporter:
    """State machine that turns raw Swift Testing output into live status lines."""

    SUITE = re.compile(r"^[◇✔✘━]\s+Suite (.+?) (started|passed|failed)")
    TEST_STARTED = re.compile(r"^◇\s+Test (?!run\b)(.+?) started")
    TEST_DONE = re.compile(r"^[✔✘━]\s+Test (?!run\b)(.+?) (passed|failed) after")
    INTERESTING = re.compile(
        r"does not match reference|^error:|Failure collecting|^SNAPSHOT_RETRY |"
        r"\*\* TEST (SUCCEEDED|FAILED) \*\*"
    )

    def __init__(
        self,
        *,
        heartbeat: float,
        status_path: Optional[Path],
        counts_path: Path,
        scheme: str,
        is_terminal: bool,
        count_images: bool,
        output: TextIO,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self.heartbeat = heartbeat
        self.status_path = status_path
        self.counts_path = counts_path
        self.scheme = scheme
        self.is_terminal = is_terminal
        self.count_images = count_images
        self.output = output
        self.clock = clock
        self.expected = {"tests": 0, "images": 0}
        if counts_path.exists():
            try:
                cached = json.loads(counts_path.read_text())
                if isinstance(cached, dict):
                    for key in self.expected:
                        value = cached.get(key)
                        if (
                            isinstance(value, int)
                            and not isinstance(value, bool)
                            and value >= 0
                        ):
                            self.expected[key] = value
            except (OSError, ValueError):
                pass
        self.started = clock()
        self.tests = 0
        self.images = 0
        self.failures = 0
        self.suite = ""
        self.current = ""
        self.last_emit = 0.0

    def run(self, lines: Iterable[str]) -> None:
        print(
            f"    (progress for {self.scheme}; full log alongside it in the work directory)",
            file=self.output,
            flush=True,
        )
        for raw in lines:
            self.consume(raw.rstrip("\n"))
        self.finish()

    def consume(self, line: str) -> None:
        # Swift Testing prefixes some parameterized results with a zero-width
        # space and uses a different glyph for passes with known issues.
        line = line.lstrip("\u200b")
        if self.count_images and line.startswith("SNAPSHOT_TIMING "):
            self.images += 1
            self.emit()
            return
        if line.startswith("FLYOVER_EXPORT "):
            self._clear_terminal()
            print(f"    {line}", file=self.output, flush=True)
            self.last_emit = 0.0
            return
        match = self.SUITE.match(line)
        if match:
            if match.group(2) == "started":
                self.suite = match.group(1)
            self.emit()
            return
        match = self.TEST_STARTED.match(line)
        if match:
            self.current = match.group(1)
            self.emit()
            return
        match = self.TEST_DONE.match(line)
        if match:
            self.tests += 1
            if match.group(2) == "failed":
                self.failures += 1
                self._clear_terminal()
                print(
                    f"    ✘ {self.suite}/{match.group(1)}",
                    file=self.output,
                    flush=True,
                )
                self.emit(force=True)
            else:
                self.current = ""
                self.emit()
            return
        if self.INTERESTING.search(line):
            self._clear_terminal()
            print(f"    {line.strip()}", file=self.output, flush=True)
            self.last_emit = 0.0

    def status(self) -> str:
        if self.expected["images"] and self.images:
            done, total, unit = self.images, self.expected["images"], "images"
        elif self.expected["tests"]:
            done, total, unit = self.tests, self.expected["tests"], "tests"
        else:
            done = self.images or self.tests
            total = 0
            unit = "images" if self.images else "tests"
        parts = [f"[{self.elapsed()}]"]
        if total and done <= total:
            parts.append(f"{done}/{total} {unit} ({int(100 * done / total)}%)")
            if done:
                remaining = (self.clock() - self.started) / done * (total - done)
                parts.append(f"~{int(remaining // 60)}:{int(remaining % 60):02d} left")
        else:
            parts.append(f"{done} {unit}")
        if self.suite:
            parts.append(self.suite)
        if self.current:
            parts.append(self.current)
        parts.append(f"{self.failures} failed" if self.failures else "ok")
        return " · ".join(parts)

    def emit(self, force: bool = False) -> None:
        now = self.clock()
        line = self.status()
        if self.status_path:
            try:
                self.status_path.write_text(line + "\n")
            except OSError:
                pass
        if self.is_terminal:
            self.output.write("\r\033[K" + line)
            self.output.flush()
        elif force or now - self.last_emit >= self.heartbeat:
            print(line, file=self.output, flush=True)
            self.last_emit = now

    def finish(self) -> None:
        self._clear_terminal()
        summary = f"    {self.tests} tests"
        if self.images:
            summary += f", {self.images} images"
        summary += f" in {self.elapsed()}"
        if self.failures:
            summary += f" — {self.failures} failed"
        elif self.tests:
            summary += " — all passed"
        else:
            summary += " — nothing ran"
        if self.tests == 0:
            summary += (
                "\n    error: this run matched no tests — check the --only identifier "
                "(Swift Testing filters at Bundle/Suite, not per function)"
            )
        print(summary, file=self.output, flush=True)
        empty_path = Path(str(self.counts_path) + ".empty")
        if self.tests:
            self.counts_path.write_text(
                json.dumps({"tests": self.tests, "images": self.images})
            )
            empty_path.unlink(missing_ok=True)
        else:
            empty_path.write_text("1")

    def elapsed(self) -> str:
        seconds = int(self.clock() - self.started)
        return f"{seconds // 60:d}:{seconds % 60:02d}"

    def _clear_terminal(self) -> None:
        if self.is_terminal:
            self.output.write("\r\033[K")
            self.output.flush()


def main(arguments: Optional[Iterable[str]] = None) -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("phase-started")
    timing = subparsers.add_parser("phase-timing")
    timing.add_argument("phase")
    timing.add_argument("started", type=int)
    timing.add_argument("scheme", nargs="?", default="")
    timing.add_argument("status", nargs="?", type=int, default=0)

    snapshots = subparsers.add_parser("snapshot-bundles")
    snapshots.add_argument("--project", type=Path, default=Path("Project.swift"))

    affected = subparsers.add_parser("affected-bundles")
    affected.add_argument("--project", type=Path, default=Path("Project.swift"))

    selection = subparsers.add_parser("selection")
    selection.add_argument("--base", default="origin/main")
    selection.add_argument("--head")
    selection.add_argument(
        "--format", choices=("text", "json", "execution"), default="text"
    )
    selection.add_argument("--skip-architecture", action="store_true")
    selection.add_argument("--skip-host-tests", action="store_true")

    filters = subparsers.add_parser("grouped-filters")
    filters.add_argument("--project", type=Path, default=Path("Project.swift"))
    filters.add_argument("--manifest", type=Path)

    progress = subparsers.add_parser("progress")
    progress.add_argument("--heartbeat", type=float, default=15)
    progress.add_argument("--status-file", type=Path)
    progress.add_argument("--counts-file", required=True, type=Path)
    progress.add_argument("--scheme", default="?")
    progress.add_argument("--count-images", action="store_true")

    failures = subparsers.add_parser("failures")
    failures.add_argument("--result", required=True)
    failures.add_argument("--tests-json", required=True, type=Path)
    failures.add_argument("--manifest", type=Path)

    options = parser.parse_args(arguments)
    if options.command == "phase-started":
        print(time.time_ns())
    elif options.command == "phase-timing":
        payload = {
            "phase": options.phase,
            "seconds": round((time.time_ns() - options.started) / 1_000_000_000, 3),
            "status": options.status,
        }
        if options.scheme:
            payload["scheme"] = options.scheme
        print("CI_TIMING " + json.dumps(payload, separators=(",", ":")), flush=True)
    elif options.command == "snapshot-bundles":
        print("\n".join(snapshot_bundles(options.project.read_text())))
    elif options.command == "selection":
        try:
            report = repository_selection(
                repository_root(__file__), options.base, options.head
            )
        except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
            print(f"error: cannot resolve affected tests: {error}", file=sys.stderr)
            print("Use an explicit scope: ./test --everything", file=sys.stderr)
            return 2
        if options.skip_architecture:
            report["independent_checks"].remove("architecture")
        if options.skip_host_tests:
            report["host_tests"] = []
            report["independent_checks"] = [
                check
                for check in report["independent_checks"]
                if check == "architecture"
            ]
        if options.format == "json":
            print(json.dumps(report, indent=2, ensure_ascii=True))
        elif options.format == "execution":
            if report["fallback_reason"]:
                print("warning: " + report["fallback_reason"], file=sys.stderr)
            if report["mode"] == "full":
                print("--everything")
            else:
                print("\n".join(report["selected"] + report["host_tests"]))
        else:
            print(describe(report))
    elif options.command == "affected-bundles":
        changed = [line for line in sys.stdin.read().splitlines() if line.strip()]
        if not changed:
            return 0
        package = json.loads(
            subprocess.run(
                ["swift", "package", "dump-package"],
                capture_output=True,
                text=True,
                check=True,
            ).stdout
        )
        try:
            selected = affected_bundles(changed, package, options.project.read_text())
        except ValueError as error:
            print(error, file=sys.stderr)
            return 2
        print("\n".join(selected))
    elif options.command == "grouped-filters":
        identifiers = sys.stdin.read().splitlines()
        try:
            if any(item.partition("/")[0] != GROUPED_BUNDLE for item in identifiers):
                suites = GroupedTestSuites.from_manifest_or_repository(
                    options.project.resolve().parent, options.manifest
                )
                identifiers = grouped_filters(identifiers, suites)
            print("\n".join(identifiers))
        except (OSError, ValueError, subprocess.CalledProcessError) as error:
            print(error, file=sys.stderr)
            return 2
    elif options.command == "progress":
        ProgressReporter(
            heartbeat=options.heartbeat,
            status_path=options.status_file,
            counts_path=options.counts_file,
            scheme=options.scheme,
            is_terminal=sys.stdout.isatty(),
            count_images=options.count_images,
            output=sys.stdout,
        ).run(sys.stdin)
    elif options.command == "failures":
        try:
            with options.tests_json.open() as stream:
                document = json.load(stream)
        except (OSError, ValueError):
            return 0
        report = failure_report(document, options.result, manifest=options.manifest)
        if report:
            print(report)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
