"""Validate, translate, and run the repository's TLA+ manifests.

The repository launcher owns discovery and the pinned TLC download. This module
owns structured manifest validation, isolated PlusCal translation, command
construction, execution, and reporting so those behaviors can be tested without
Java or TLC.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Mapping, Sequence, TextIO


TLC_VERSION = "1.7.4"
PLUSCAL_VERSION = "1.11"
JAVA_VERSION = "temurin-21.0.8+9.0.LTS"
TLC_SHA256 = "936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88"
CLEAN_CHECK_MESSAGE = "Model checking completed. No error has been found."


class TlaCheckError(Exception):
    """A manifest, fixture, translation, or TLC result failed validation."""


@dataclass(frozen=True)
class TlaCase:
    name: str
    config: str
    expectation: str
    output_contains: str | None


@dataclass(frozen=True)
class TlaManifest:
    source: str
    module: str
    cases: tuple[TlaCase, ...]


@dataclass(frozen=True)
class ToolVersions:
    tlc: str
    pluscal: str
    java: str
    tla2tools_sha256: str


ProcessRunner = Callable[..., subprocess.CompletedProcess[str]]
MonotonicClock = Callable[[], float]


def _required_string(value: object, field: str, manifest_path: Path) -> str:
    if not isinstance(value, str) or not value:
        raise TlaCheckError(f"error: {manifest_path}: {field} must be a non-empty string")
    return value


def load_manifest(manifest_path: Path) -> TlaManifest:
    try:
        payload = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise TlaCheckError(f"error: could not read {manifest_path}: {error}") from error

    if not isinstance(payload, dict):
        raise TlaCheckError(f"error: {manifest_path}: root must be an object")
    source = _required_string(payload.get("source"), "source", manifest_path)
    if source not in ("pluscal", "tla"):
        raise TlaCheckError(
            f"error: {manifest_path}: source must be 'pluscal' or 'tla'"
        )
    module = _required_string(payload.get("module"), "module", manifest_path)
    raw_cases = payload.get("cases")
    if not isinstance(raw_cases, list) or not raw_cases:
        raise TlaCheckError(f"error: {manifest_path}: cases must be a non-empty array")

    cases: list[TlaCase] = []
    names: set[str] = set()
    for index, raw_case in enumerate(raw_cases):
        if not isinstance(raw_case, dict):
            raise TlaCheckError(f"error: {manifest_path}: case {index} must be an object")
        name = _required_string(raw_case.get("name"), f"case {index} name", manifest_path)
        if name in names:
            raise TlaCheckError(f"error: {manifest_path}: duplicate case name {name!r}")
        names.add(name)
        config = _required_string(
            raw_case.get("config"), f"case {name!r} config", manifest_path
        )
        expectation = _required_string(
            raw_case.get("expect"), f"case {name!r} expect", manifest_path
        )
        if expectation not in ("pass", "fail"):
            raise TlaCheckError(
                f"error: {manifest_path}: case {name!r} has unknown expect {expectation!r}"
            )
        output_contains = raw_case.get("outputContains")
        if output_contains is not None and not isinstance(output_contains, str):
            raise TlaCheckError(
                f"error: {manifest_path}: case {name!r} outputContains must be a string"
            )
        cases.append(TlaCase(name, config, expectation, output_contains))

    return TlaManifest(source, module, tuple(cases))


def java_command_prefix(
    environment: Mapping[str, str], java_version: str = JAVA_VERSION
) -> list[str]:
    java = environment.get("TLA_JAVA")
    if java:
        return [java]
    return [
        "mise",
        "--yes",
        "--no-config",
        "x",
        f"java@{java_version}",
        "--",
        "java",
    ]


def pluscal_command(
    java_prefix: Sequence[str], jar_path: Path, module: str
) -> list[str]:
    return [
        *java_prefix,
        "-cp",
        str(jar_path),
        "pcal.trans",
        "-nocfg",
        "-unixEOL",
        module,
    ]


def tlc_command(
    java_prefix: Sequence[str],
    jar_path: Path,
    module: str,
    config: str,
    state_directory: Path,
) -> list[str]:
    return [
        *java_prefix,
        "-XX:+UseParallelGC",
        "-Xmx1g",
        "-jar",
        str(jar_path),
        "-cleanup",
        "-difftrace",
        "-metadir",
        str(state_directory),
        "-config",
        config,
        module,
    ]


def parse_stats(output: str, elapsed: float) -> dict[str, object]:
    state_matches = re.findall(
        r"([0-9,]+) states generated, ([0-9,]+) distinct states found, "
        r"([0-9,]+) states left on queue\.",
        output,
    )
    depth_matches = re.findall(
        r"The depth of the complete state graph search is ([0-9,]+)\.", output
    )
    stats: dict[str, object] = {"elapsedSeconds": round(elapsed, 3)}
    if state_matches:
        generated, distinct, queued = state_matches[-1]
        stats.update(
            generatedStates=int(generated.replace(",", "")),
            distinctStates=int(distinct.replace(",", "")),
            statesLeftOnQueue=int(queued.replace(",", "")),
        )
    if depth_matches:
        stats["depth"] = int(depth_matches[-1].replace(",", ""))
    return stats


def stats_text(stats: Mapping[str, object]) -> str:
    elapsed = float(stats["elapsedSeconds"])
    if "generatedStates" not in stats:
        return f"{elapsed:.3f}s"
    return (
        f"{stats['generatedStates']} generated, "
        f"{stats['distinctStates']} distinct, "
        f"depth {stats.get('depth', '?')}, "
        f"{elapsed:.3f}s"
    )


def _checksum(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _write_summary(path: Path, summary: Mapping[str, object]) -> None:
    path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")


def run_manifest(
    manifest_path: Path,
    spec_directory: Path,
    run_directory: Path,
    jar_path: Path,
    versions: ToolVersions,
    *,
    environment: Mapping[str, str] | None = None,
    process_runner: ProcessRunner | None = None,
    output: TextIO = sys.stdout,
    monotonic: MonotonicClock = time.monotonic,
) -> None:
    manifest = load_manifest(manifest_path)
    module_path = spec_directory / manifest.module
    if not module_path.is_file():
        raise TlaCheckError(
            f"error: {spec_directory.name} manifest module {manifest.module!r} not found"
        )

    for case in manifest.cases:
        config_path = spec_directory / case.config
        if not config_path.is_file():
            raise TlaCheckError(
                f"error: {manifest_path}: case {case.name!r} "
                f"config {case.config!r} not found"
            )

    generated_directory = run_directory / "generated"
    logs_directory = run_directory / "logs"
    states_directory = run_directory / "states"
    run_directory.mkdir(parents=True, exist_ok=True)
    shutil.copytree(spec_directory, generated_directory)
    logs_directory.mkdir()
    states_directory.mkdir()

    source_hash = _checksum(module_path)
    java_prefix = java_command_prefix(environment or os.environ, versions.java)
    runner = process_runner or subprocess.run
    summary_path = run_directory / "summary.json"
    summary: dict[str, object] = {
        "spec": spec_directory.name,
        "source": manifest.source,
        "tools": {
            "tlc": versions.tlc,
            "pluscal": versions.pluscal,
            "java": versions.java,
            "tla2toolsSHA256": versions.tla2tools_sha256,
        },
        "translation": {
            "status": "pending" if manifest.source == "pluscal" else "not-required",
            "module": f"generated/{manifest.module}",
        },
        "cases": [],
    }
    _write_summary(summary_path, summary)

    try:
        if manifest.source == "pluscal":
            print(f"  translating {manifest.module}", file=output, flush=True)
            translation = runner(
                pluscal_command(java_prefix, jar_path, manifest.module),
                cwd=generated_directory,
            )
            translation_summary = summary["translation"]
            assert isinstance(translation_summary, dict)
            if translation.returncode != 0:
                translation_summary["status"] = "failed"
                _write_summary(summary_path, summary)
                raise TlaCheckError(f"  FAIL translation; see {run_directory}")
            translation_summary["status"] = "generated"
            _write_summary(summary_path, summary)

        for case in manifest.cases:
            state_directory = states_directory / case.name
            state_directory.mkdir()
            command = tlc_command(
                java_prefix,
                jar_path,
                manifest.module,
                case.config,
                state_directory,
            )
            started = monotonic()
            result = runner(
                command,
                capture_output=True,
                text=True,
                cwd=generated_directory,
            )
            elapsed = monotonic() - started
            combined_output = (result.stdout or "") + (result.stderr or "")
            log_path = logs_directory / f"{case.name}.log"
            log_path.write_text(combined_output, encoding="utf-8")

            actual = "pass" if result.returncode == 0 else "fail"
            matched_output = (
                case.output_contains is None or case.output_contains in combined_output
            )
            stats = parse_stats(combined_output, elapsed)
            case_summary = {
                "name": case.name,
                "config": case.config,
                "expected": case.expectation,
                "verdict": actual,
                "matchedFailure": (
                    case.output_contains
                    if case.output_contains is not None and matched_output
                    else None
                ),
                "stats": stats,
                "log": f"logs/{case.name}.log",
            }
            cases_summary = summary["cases"]
            assert isinstance(cases_summary, list)
            cases_summary.append(case_summary)
            _write_summary(summary_path, summary)

            if case.expectation == "pass":
                if result.returncode != 0:
                    raise TlaCheckError(
                        f"  FAIL {case.name}: expected pass, TLC exited "
                        f"{result.returncode}; see {log_path}\n{combined_output[-4000:]}"
                    )
                if CLEAN_CHECK_MESSAGE not in combined_output:
                    raise TlaCheckError(
                        f"  FAIL {case.name}: TLC did not report a clean check; "
                        f"see {log_path}"
                    )
                print(
                    f"  ok   {case.name} (pass; {stats_text(stats)})",
                    file=output,
                    flush=True,
                )
            else:
                if result.returncode == 0:
                    raise TlaCheckError(
                        f"  FAIL {case.name}: expected failure, TLC passed; "
                        f"see {log_path}"
                    )
                if not matched_output:
                    raise TlaCheckError(
                        f"  FAIL {case.name}: expected output to contain "
                        f"{case.output_contains!r}; see {log_path}\n"
                        f"{combined_output[-4000:]}"
                    )
                print(
                    f"  ok   {case.name} (expected failure; {stats_text(stats)})",
                    file=output,
                    flush=True,
                )

        print(f"  artifacts: {run_directory}", file=output, flush=True)
    finally:
        try:
            source_is_unchanged = _checksum(module_path) == source_hash
        except OSError:
            source_is_unchanged = False
        if not source_is_unchanged:
            raise TlaCheckError(
                f"error: tracked model source changed while checking: {module_path}"
            )


def main(arguments: Sequence[str]) -> int:
    if len(arguments) != 8:
        print(
            "usage: tla_check.py MANIFEST SPEC_DIR RUN_DIR TLA2TOOLS_JAR "
            "TLC_VERSION PLUSCAL_VERSION JAVA_VERSION TLA2TOOLS_SHA256",
            file=sys.stderr,
        )
        return 2
    manifest, spec, run, jar = (Path(argument) for argument in arguments[:4])
    versions = ToolVersions(*arguments[4:])
    try:
        run_manifest(manifest, spec, run, jar, versions)
    except (OSError, TlaCheckError) as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
