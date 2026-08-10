"""Validate TLA+ manifests and run their TLC cases.

The repository launcher owns discovery and the pinned TLC download. This module
owns structured manifest validation, command construction, execution, and
reporting so those behaviors can be tested without Java or TLC.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Mapping, Sequence, TextIO


JAVA_VERSION = "temurin-21.0.8+9.0.LTS"
CLEAN_CHECK_MESSAGE = "Model checking completed. No error has been found."


class TlaCheckError(Exception):
    """A manifest, fixture, or TLC result failed validation."""


@dataclass(frozen=True)
class TlaCase:
    name: str
    config: str
    expectation: str
    output_contains: str | None


@dataclass(frozen=True)
class TlaManifest:
    module: str
    cases: tuple[TlaCase, ...]


ProcessRunner = Callable[..., subprocess.CompletedProcess[str]]


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

    return TlaManifest(module, tuple(cases))


def java_command_prefix(environment: Mapping[str, str]) -> list[str]:
    java = environment.get("TLA_JAVA")
    if java:
        return [java]
    return [
        "mise",
        "--yes",
        "--no-config",
        "x",
        f"java@{JAVA_VERSION}",
        "--",
        "java",
    ]


def tlc_command(
    java_prefix: Sequence[str],
    jar_path: Path,
    module_path: Path,
    config_path: Path,
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
        str(config_path),
        str(module_path),
    ]


def run_manifest(
    manifest_path: Path,
    spec_directory: Path,
    logs_directory: Path,
    states_directory: Path,
    jar_path: Path,
    *,
    environment: Mapping[str, str] | None = None,
    process_runner: ProcessRunner | None = None,
    output: TextIO = sys.stdout,
) -> None:
    manifest = load_manifest(manifest_path)
    module_path = spec_directory / manifest.module
    if not module_path.is_file():
        raise TlaCheckError(
            f"error: {spec_directory.name} manifest module {manifest.module!r} not found"
        )

    case_paths: list[tuple[TlaCase, Path]] = []
    for case in manifest.cases:
        config_path = spec_directory / case.config
        if not config_path.is_file():
            raise TlaCheckError(
                f"error: {manifest_path}: case {case.name!r} config {case.config!r} not found"
            )
        case_paths.append((case, config_path))

    logs_directory.mkdir(parents=True, exist_ok=True)
    states_directory.mkdir(parents=True, exist_ok=True)
    runner = process_runner or subprocess.run
    java_prefix = java_command_prefix(environment or os.environ)

    for case, config_path in case_paths:
        state_directory = states_directory / case.name
        state_directory.mkdir(parents=True, exist_ok=True)
        command = tlc_command(
            java_prefix,
            jar_path,
            module_path,
            config_path,
            state_directory,
        )
        result = runner(command, capture_output=True, text=True)
        combined_output = (result.stdout or "") + (result.stderr or "")
        log_path = logs_directory / f"{case.name}.log"
        log_path.write_text(combined_output, encoding="utf-8")

        if case.expectation == "pass":
            if result.returncode != 0:
                raise TlaCheckError(
                    f"  FAIL {case.name}: expected pass, TLC exited {result.returncode}; "
                    f"see {log_path}\n{combined_output[-4000:]}"
                )
            if CLEAN_CHECK_MESSAGE not in combined_output:
                raise TlaCheckError(
                    f"  FAIL {case.name}: TLC did not report a clean check; see {log_path}"
                )
            print(f"  ok   {case.name} (pass)", file=output)
        else:
            if result.returncode == 0:
                raise TlaCheckError(
                    f"  FAIL {case.name}: expected failure, TLC passed; see {log_path}"
                )
            if case.output_contains and case.output_contains not in combined_output:
                raise TlaCheckError(
                    f"  FAIL {case.name}: expected output to contain "
                    f"{case.output_contains!r}; see {log_path}\n{combined_output[-4000:]}"
                )
            print(f"  ok   {case.name} (expected failure)", file=output)

    print(f"  artifacts: {logs_directory.parent}", file=output)


def main(arguments: Sequence[str]) -> int:
    if len(arguments) != 5:
        print(
            "usage: tla_check.py MANIFEST SPEC_DIR LOGS_DIR STATES_DIR TLA2TOOLS_JAR",
            file=sys.stderr,
        )
        return 2
    try:
        run_manifest(*(Path(argument) for argument in arguments))
    except (OSError, TlaCheckError) as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
