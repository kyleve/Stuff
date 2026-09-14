#!/usr/bin/env python3
"""Build both Porthole compiler paths and compare the actual compiler invocations."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys


CONFIGURATIONS = {
    "Debug": ("Where Development", "-Onone", "WHERE_DEVELOPMENT"),
    "Beta": ("Where Beta", "-O", "WHERE_BETA"),
    "Release": ("Where App Store", "-O", "WHERE_APP_STORE"),
}
DESTINATIONS = {"iphonesimulator": "generic/platform=iOS Simulator", "iphoneos": "generic/platform=iOS"}
GUARD = "PORTHOLE_ORIGINAL_SOURCE_CHECK"
PRIVATE_FLAGS = {"-disable-access-control", "-enable-private-imports"}
UNSAFE_EXTENSION = re.compile(
    rb"(?:warning:|error:|ld:).*?(?:not safe for use in (?:application|app) extensions|"
    rb"unavailable in (?:application|app) extensions|extension[- ]unsafe|"
    rb"(?:application|app) extensions?.*unavailable)", re.IGNORECASE
)
MAX_BUILD_LOG_BYTES = 1024 * 1024 * 1024
MAX_BUILD_LOG_LINE_BYTES = 4 * 1024 * 1024


def environment(base: dict[str, str], original: bool, configuration: str) -> dict[str, str]:
    result = dict(base)
    # Both the Package.swift process and Tuist's manifest environment must agree.
    result[GUARD] = "1" if original else "0"
    result["TUIST_" + GUARD] = result[GUARD]
    result["PORTHOLE_BUILD_CONFIGURATION"] = configuration
    for name in ("SDKROOT", "SWIFT_EXEC"):
        result.pop(name, None)
    return result


def build_command(configuration: str, sdk: str, sdk_path: Path, derived_data: Path, jobs: int) -> list[str]:
    if jobs < 1:
        raise ValueError("Build jobs must be a positive integer.")
    scheme, _, _ = CONFIGURATIONS[configuration]
    return [
        "mise", "exec", "--", "xcodebuild", "build", "-workspace", "Stuff.xcworkspace",
        "-scheme", scheme, "-configuration", configuration, "-sdk", str(sdk_path),
        "-destination", DESTINATIONS[sdk], "-derivedDataPath", str(derived_data), "-jobs", str(jobs),
        "ARCHS=arm64", "ONLY_ACTIVE_ARCH=YES", "CODE_SIGNING_ALLOWED=NO",
    ]


def exported_modules(package: dict) -> set[str]:
    modules = {target["name"] for target in package["targets"]
               if any((item.get("plugin") or [None])[0] == "PortholeBuildPlugin"
                      for item in target.get("pluginUsages", []))}
    if not modules:
        raise ValueError("The package has no Porthole adopting modules.")
    return modules | {"Where"}


def argument(tokens: list[str], flag: str) -> str:
    try:
        return tokens[tokens.index(flag) + 1]
    except (ValueError, IndexError) as error:
        raise ValueError(f"The compiler command has no value for {flag}.") from error


def definitions(tokens: list[str]) -> set[str]:
    result = set()
    for index, token in enumerate(tokens):
        if token == "-D":
            if index + 1 == len(tokens):
                raise ValueError("The compiler command has an incomplete -D condition.")
            result.add(tokens[index + 1])
        elif token.startswith("-D"):
            result.add(token[2:])
    return result


def compiler_evidence(log: Path, modules: set[str], configuration: str, sdk: str,
                      sdk_path: Path, compiler_path: Path, original: bool) -> dict:
    """Inspect real Swift driver commands, including each package-target compilation."""
    result = {}
    _, app_optimization, audience = CONFIGURATIONS[configuration]
    with log.open() as stream:
        for line in stream:
            if " -module-name " not in line or not re.search(r"/swiftc[\"']?\s", line):
                continue
            tokens = shlex.split(line)
            module = argument(tokens, "-module-name")
            if module not in modules:
                continue
            executable = next(token for token in tokens if Path(token).name == "swiftc")
            if Path(executable).resolve().parent != compiler_path.resolve().parent:
                raise ValueError(f"{module} used a different Swift toolchain: {executable}")
            actual_sdk = Path(argument(tokens, "-sdk")).resolve()
            if actual_sdk != sdk_path.resolve():
                raise ValueError(f"{module} used a different SDK: {actual_sdk}")
            target = argument(tokens, "-target")
            if not target.startswith("arm64-apple-ios") or ("-simulator" in target) != (sdk == "iphonesimulator"):
                raise ValueError(f"{module} used a different destination or architecture: {target}")
            optimizations = set(tokens) & {"-Onone", "-O", "-Osize", "-Ounchecked"}
            if len(optimizations) != 1:
                raise ValueError(f"{module} has ambiguous optimization settings: {sorted(optimizations)}")
            optimization = next(iter(optimizations))
            if module == "Where" and optimization != app_optimization:
                raise ValueError(f"Where did not use {app_optimization}: {optimization}")
            actual_mode = "wholemodule" if set(tokens) & {"-whole-module-optimization", "-wmo"} else "singlefile"
            flags = set(tokens) & PRIVATE_FLAGS
            if flags != (set() if original else PRIVATE_FLAGS):
                raise ValueError(f"{module} used incorrect private-access flags: {sorted(flags)}")
            conditions = definitions(tokens)
            if (GUARD in conditions) != original:
                raise ValueError(f"{module} used an incorrect {GUARD} condition.")
            if module == "Where" and audience not in conditions:
                raise ValueError(f"Where has no {audience} audience condition.")
            facts = {"sdk": str(actual_sdk), "target": target, "optimization": optimization,
                     "compilationMode": actual_mode, "conditions": sorted(conditions - {GUARD}),
                     "swiftVersion": argument(tokens, "-swift-version"),
                     "toolchain": str(compiler_path.resolve().parent)}
            if module in result and result[module] != facts:
                raise ValueError(f"{module} has inconsistent compiler invocations in {log.name}.")
            result[module] = facts
    missing = modules - result.keys()
    if missing:
        raise ValueError("No compiler invocation was recorded for: " + ", ".join(sorted(missing)))
    return dict(sorted(result.items()))


def compare(original: dict, instrumented: dict) -> None:
    if original.keys() != instrumented.keys():
        raise ValueError("The original and instrumented builds compiled different module sets.")
    for module in original:
        if original[module] != instrumented[module]:
            raise ValueError(f"{module} has different compiler settings between the original and instrumented builds.")


def compare_packaging(original: dict, instrumented: dict) -> None:
    """Only documented Year input-type ordering is normalized by the packaging checker."""
    for key in ("configuration", "sdk"):
        if original[key] != instrumented[key]:
            raise ValueError(f"The compiler pair has different packaging {key}.")
    def comparable_resources(report):
        return {host: {module: {key: entry[key] for key in ("files", "crossBuildSHA256", "opaqueCompiledFiles")}
                       for module, entry in modules.items()} for host, modules in report["resources"].items()}
    if comparable_resources(original) != comparable_resources(instrumented):
        raise ValueError("The compiler pair has different packaging resources.")
    if original["appIntents"]["semanticSHA256"] != instrumented["appIntents"]["semanticSHA256"]:
        raise ValueError("The compiler pair has different App Intents metadata.")


def check_extension_diagnostics(log: Path) -> None:
    """Reject extension-unsafe diagnostics even when xcodebuild exits successfully."""
    for path in (log, log.with_suffix(".stderr.log")):
        if path.stat().st_size > MAX_BUILD_LOG_BYTES:
            raise ValueError(f"Build log exceeds the bounded diagnostic scan: {path.name}")
        with path.open("rb") as stream:
            line_number = 0
            while line := stream.readline(MAX_BUILD_LOG_LINE_BYTES + 1):
                line_number += 1
                if len(line) > MAX_BUILD_LOG_LINE_BYTES:
                    raise ValueError(f"Build log line exceeds the diagnostic scan bound: {path.name}:{line_number}")
                if UNSAFE_EXTENSION.search(line):
                    raise ValueError(f"Extension-unsafe diagnostic in {path.name}:{line_number}; inspect the retained build log.")


def run_command(command: list[str], *, root: Path, env: dict[str, str], log: Path) -> None:
    # Manifest and tool-identity output must remain parseable when tools emit warnings.
    with log.open("w") as output, log.with_suffix(".stderr.log").open("w") as errors:
        subprocess.run(command, cwd=root, env=env, stdout=output, stderr=errors, check=True)


def run_contract(root: Path, output: Path, configuration: str, sdk: str, jobs: int, *, run=run_command) -> dict:
    """Use fresh products for each path, and leave a durable result even when a step fails."""
    if jobs < 1:
        raise ValueError("Build jobs must be a positive integer.")
    if output.exists():
        raise ValueError(f"The output directory already exists: {output}. Use a new directory for fresh compiler evidence.")
    output.mkdir(parents=True)
    record = {"configuration": configuration, "sdk": sdk, "jobs": jobs, "state": "running", "steps": []}
    report = output / "result.json"

    def save() -> None:
        temporary = output / "result.json.tmp"
        temporary.write_text(json.dumps(record, indent=2) + "\n")
        temporary.replace(report)

    def command(name: str, argv: list[str], env: dict[str, str]) -> Path:
        log = output / (name + ".log")
        record["steps"].append({"name": name, "command": argv, "log": log.name, "state": "running"})
        save()
        print(f"Porthole compiler contract: {name}", flush=True)
        run(argv, root=root, env=env, log=log)
        if name.endswith("-build"):
            check_extension_diagnostics(log)
        record["steps"][-1]["state"] = "passed"
        save()
        return log

    try:
        env = environment(os.environ, False, configuration)
        version = command("xcode-version", ["xcodebuild", "-version"], env).read_text()
        pinned = (root / ".xcode-build-version").read_text().strip()
        actual_version = re.search(r"^Build version (.+)$", version, re.MULTILINE)
        if actual_version is None or actual_version.group(1) != pinned:
            raise ValueError(f"Select the pinned Xcode build {pinned} before this compiler check.")
        record["xcode"] = version.strip()
        compiler_path = Path(command("compiler-path", ["xcrun", "--find", "swiftc"], env).read_text().strip())
        record["compiler"] = command("compiler-version", ["xcrun", "swiftc", "--version"], env).read_text().strip()
        sdk_path = Path(command("sdk-path", ["xcrun", "--sdk", sdk, "--show-sdk-path"], env).read_text().strip())
        paired_evidence = {}
        for name, original in [("original", True), ("instrumented", False)]:
            env = environment(os.environ, original, configuration)
            package_log = command(name + "-package", ["swift", "package", "dump-package"], env)
            modules = exported_modules(json.loads(package_log.read_text()))
            command(name + "-generate", ["./ide", "--no-open"], env)
            log = command(name + "-build", build_command(configuration, sdk, sdk_path, output / (name + "-products"), jobs), env)
            paired_evidence[name] = compiler_evidence(log, modules, configuration, sdk, sdk_path, compiler_path, original)
            record[name] = paired_evidence[name]
            save()
        compare(paired_evidence["original"], paired_evidence["instrumented"])
        packaging = {}
        for name, original in [("original", True), ("instrumented", False)]:
            packaging_report = output / (name + "-packaging.json")
            app = output / (name + "-products") / "Build/Products" / (configuration + "-" + sdk) / "Where.app"
            command(name + "-packaging", [sys.executable, str(root / "Tools/porthole_packaging.py"),
                    "--app", str(app), "--repository", str(root), "--configuration", configuration,
                    "--sdk", sdk, "--output", str(packaging_report)], environment(os.environ, original, configuration))
            packaging[name] = json.loads(packaging_report.read_text())
            if packaging[name].get("status") != "passed":
                raise ValueError(f"{name} packaging did not pass.")
            record[name + "Packaging"] = packaging_report.name
            save()
        compare_packaging(packaging["original"], packaging["instrumented"])
        record["state"] = "passed"
        save()
        return record
    except Exception as error:
        record["state"] = "failed"
        record["error"] = str(error)
        if record["steps"] and record["steps"][-1]["state"] == "running":
            record["steps"][-1]["state"] = "failed"
        save()
        raise


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--configuration", required=True, choices=CONFIGURATIONS)
    parser.add_argument("--sdk", required=True, choices=DESTINATIONS)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--jobs", type=int, default=2, help="Maximum concurrent build tasks (default: 2).")
    args = parser.parse_args(argv)
    try:
        run_contract(Path(__file__).resolve().parents[1], args.output.resolve(), args.configuration, args.sdk, args.jobs)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
