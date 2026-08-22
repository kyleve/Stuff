"""Structured scope and reporting support for the public ``./test`` command."""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
from typing import Callable, Iterable, Mapping, Optional, Sequence, TextIO

from xcode_results import test_cases


DECLARATION = re.compile(r"^ {8}(?:unitTests\(|\.target\()", re.MULTILINE)
GLOBAL_PATHS = {
    "Package.swift",
    "Package.resolved",
    "Project.swift",
    "Tuist.swift",
    ".swiftformat",
    ".mise.toml",
    "test",
    "simulator",
    "ide",
}


def snapshot_bundles(project_text: str) -> list[str]:
    return sorted(set(re.findall(r'name:\s*"(\w+SnapshotTests)"', project_text)))


def affected_bundles(
    changed: Sequence[str],
    package: Mapping[str, object],
    project_text: str,
) -> list[str]:
    """Resolve changed paths to test bundles without silently under-selecting."""

    if not changed:
        return []

    paths: dict[str, str] = {}
    dependencies: dict[str, list[str]] = {}
    for target in package["targets"]:
        name = target["name"]
        paths[name] = str(target.get("path") or "").rstrip("/")
        names = []
        for dependency in target.get("dependencies", []):
            for key in ("byName", "target", "product"):
                if key in dependency:
                    names.append(dependency[key][0])
                    break
        dependencies[name] = names

    reverse: dict[str, set[str]] = {}
    for name, target_dependencies in dependencies.items():
        for dependency in target_dependencies:
            reverse.setdefault(dependency, set()).add(name)

    declarations = _declarations(project_text)
    bundles = _bundles(declarations)
    problems = _parse_problems(bundles)
    if problems:
        raise ValueError("could not read Project.swift reliably: " + "; ".join(problems))

    selected: set[str] = set()
    changed_targets: set[str] = set()
    everything = False
    for path in changed:
        if path in GLOBAL_PATHS or path.startswith(".github/"):
            everything = True
            continue
        owner = next(
            (
                name
                for name, bundle in bundles.items()
                if bundle["sources"]
                and path.startswith(str(bundle["sources"]) + "/")
            ),
            None,
        )
        if owner:
            selected.add(owner)
            continue
        target = next(
            (
                name
                for name, source in paths.items()
                if source and path.startswith(source + "/")
            ),
            None,
        )
        if target:
            changed_targets.add(target)
            continue
        module = "/".join(path.split("/")[:2])
        for name, bundle in bundles.items():
            if str(bundle["sources"]).startswith(module + "/"):
                selected.add(name)

    if everything:
        return sorted(bundles)

    frontier = list(changed_targets)
    affected = set(changed_targets)
    while frontier:
        target = frontier.pop()
        for dependent in reverse.get(target, ()):
            if dependent not in affected:
                affected.add(dependent)
                frontier.append(dependent)

    for name, bundle in bundles.items():
        if set(bundle["products"]) & affected:
            selected.add(name)
    return sorted(selected)


def failure_report(document: Mapping[str, object], result_path: str) -> str:
    failures = [case for case in test_cases(document) if case.result == "failed"]
    lines: list[str] = []
    for case in failures:
        lines.append(f"  {case.display_identifier}")
        lines.append(f"      ./test --only '{case.suite_identifier}'")
    if failures:
        lines.extend(["", f"  Result bundle: {result_path}"])
    return "\n".join(lines)


class ProgressReporter:
    """State machine that turns raw Swift Testing output into live status lines."""

    SUITE = re.compile(r"^[◇✔✘]\s+Suite (\S+) (started|passed|failed)")
    TEST_STARTED = re.compile(r"^◇\s+Test (?!run\b)(\S+?) started")
    TEST_DONE = re.compile(r"^[✔✘]\s+Test (?!run\b)(\S+?) (passed|failed) after")
    INTERESTING = re.compile(
        r"does not match reference|^error:|Failure collecting|"
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
                        if isinstance(value, int) and not isinstance(value, bool) and value >= 0:
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
        if self.count_images and line.startswith("SNAPSHOT_TIMING "):
            self.images += 1
            self.emit()
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


def _declarations(project_text: str) -> dict[str, str]:
    starts = [match.start() for match in DECLARATION.finditer(project_text)]
    starts.append(len(project_text))
    declarations = {}
    for index, start in enumerate(starts[:-1]):
        window = project_text[start : starts[index + 1]]
        name = re.search(r'name:\s*"(\w+)"', window)
        if name:
            declarations[name.group(1)] = window
    return declarations


def _products_in(window: str) -> set[str]:
    found = set(re.findall(r'\.package\(product:\s*"(\w+)"\)', window))
    dependency = re.search(r'productDependency:\s*"(\w+)"', window)
    if dependency:
        found.add(dependency.group(1))
    extra = re.search(r'extraPackageProducts:\s*\[([^\]]*)\]', window)
    if extra:
        found.update(re.findall(r'"(\w+)"', extra.group(1)))
    return found


def _bundles(declarations: Mapping[str, str]) -> dict[str, dict[str, object]]:
    bundles = {}
    for name, window in declarations.items():
        sources = re.search(r'sources:\s*\[\s*"([^"]+)"', window)
        if not sources or not name.endswith("Tests"):
            continue
        products = _products_in(window)
        hosts = [
            host
            for host in re.findall(r'\.target\(name:\s*"(\w+)"\)', window)
            if host in declarations
        ]
        for host in hosts:
            products |= _products_in(declarations[host])
        bundles[name] = {
            "sources": sources.group(1).replace("/**", "").rstrip("/"),
            "products": products,
            "hostedByTarget": bool(hosts),
        }
    return bundles


def _parse_problems(bundles: Mapping[str, Mapping[str, object]]) -> list[str]:
    problems = []
    if len(bundles) < 15:
        problems.append(f"only found {len(bundles)} test bundles")
    for name, bundle in bundles.items():
        if not bundle["sources"]:
            problems.append(f"{name} has no sources")
        if not bundle["products"] and not bundle["hostedByTarget"]:
            problems.append(f"{name} links neither a package product nor a target")
    return problems


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

    progress = subparsers.add_parser("progress")
    progress.add_argument("--heartbeat", type=float, default=15)
    progress.add_argument("--status-file", type=Path)
    progress.add_argument("--counts-file", required=True, type=Path)
    progress.add_argument("--scheme", default="?")
    progress.add_argument("--count-images", action="store_true")

    failures = subparsers.add_parser("failures")
    failures.add_argument("--result", required=True)
    failures.add_argument("--tests-json", required=True, type=Path)

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
        report = failure_report(document, options.result)
        if report:
            print(report)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
