#!/usr/bin/env python3
"""Read completed app bundles and explicit runtime samples without building or launching apps."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import math
from pathlib import Path
import plistlib
import statistics
import stat
import struct
import sys


CONFIGURATIONS = ("Debug", "Beta", "Release")
METRICS = ("launchMilliseconds", "residentBytes")
CATALOG_SIZE_DEFINITION = (
    "standalonePortholeCatalogFileBytes counts only standalone .porthole.json files. "
    "portholeCatalogBytes is a compatibility alias for that value. "
    "Embedded API catalogs and source archives remain part of their executable or framework files and the logicalBytes total. "
    "This report does not isolate the size of embedded catalogs or source archives."
)


def executable_architectures(path: Path) -> list[dict]:
    """Read CPU identities from thin or universal Mach-O headers, without executing tools."""
    thin_formats = {
        b"\xce\xfa\xed\xfe": ("<", 28), b"\xfe\xed\xfa\xce": (">", 28),
        b"\xcf\xfa\xed\xfe": ("<", 32), b"\xfe\xed\xfa\xcf": (">", 32),
    }
    fat_formats = {
        b"\xca\xfe\xba\xbe": (">", "IIIII"), b"\xbe\xba\xfe\xca": ("<", "IIIII"),
        b"\xca\xfe\xba\xbf": (">", "IIQQII"), b"\xbf\xba\xfe\xca": ("<", "IIQQII"),
    }
    names = {
        (7, 3): "i386", (0x01000007, 3): "x86_64", (0x01000007, 8): "x86_64h",
        (12, 0): "arm", (12, 6): "armv6", (12, 9): "armv7", (12, 10): "armv7f",
        (12, 11): "armv7s", (12, 12): "armv7k", (12, 13): "armv8",
        (12, 14): "armv6m", (12, 15): "armv7m", (12, 16): "armv7em",
        (0x0100000C, 0): "arm64", (0x0100000C, 1): "arm64v8", (0x0100000C, 2): "arm64e",
        (0x0200000C, 1): "arm64_32",
    }
    with path.open("rb") as stream:
        file_size = stream.seek(0, 2)

        def read(offset: int, size: int, end: int) -> bytes:
            if offset < 0 or size < 0 or offset + size > end:
                raise ValueError("Incomplete Mach-O executable: header or slice extends beyond its bounds")
            stream.seek(offset)
            data = stream.read(size)
            if len(data) != size:
                raise ValueError("Incomplete Mach-O executable: truncated header or slice")
            return data

        def thin_architecture(offset: int, size: int) -> dict:
            end = offset + size
            magic = read(offset, 4, end)
            if magic not in thin_formats:
                raise ValueError("Unrecognized executable data: expected a Mach-O header")
            byte_order, header_size = thin_formats[magic]
            header = read(offset, header_size, end)
            cpu_type, cpu_subtype, file_type, commands, command_bytes, _ = struct.unpack_from(byte_order + "6I", header, 4)
            if file_type != 2:
                raise ValueError("Expected a Mach-O executable (MH_EXECUTE)")
            if command_bytes > size - header_size or commands > command_bytes // 8:
                raise ValueError("Incomplete Mach-O executable: invalid load-command bounds")
            name = names.get((cpu_type, cpu_subtype & 0x00FFFFFF))
            if name is None:
                raise ValueError(f"Unrecognized Mach-O architecture: CPU type {cpu_type:#x}, subtype {cpu_subtype:#x}")
            if (header_size == 32) != bool(cpu_type & 0x03000000):
                raise ValueError("Mach-O header width disagrees with its CPU type")
            # Preserve subtype capability/ABI bits, even when the familiar name is the same.
            return {"name": name, "cpuType": cpu_type, "cpuSubtype": cpu_subtype}

        magic = read(0, 4, file_size)
        if magic in thin_formats:
            return [thin_architecture(0, file_size)]
        if magic not in fat_formats:
            raise ValueError("Unrecognized executable data: expected a thin or universal Mach-O binary")
        byte_order, entry_format = fat_formats[magic]
        count = struct.unpack(byte_order + "I", read(4, 4, file_size))[0]
        entry_size = struct.calcsize(byte_order + entry_format)
        if count == 0 or count > (file_size - 8) // entry_size:
            raise ValueError("Incomplete universal Mach-O executable: invalid architecture table")
        table_end = 8 + count * entry_size
        architectures = []
        ranges = []
        for index in range(count):
            entry = struct.unpack(byte_order + entry_format, read(8 + index * entry_size, entry_size, table_end))
            cpu_type, cpu_subtype, offset, size = entry[:4]
            if offset < table_end or size == 0 or offset + size > file_size:
                raise ValueError("Incomplete universal Mach-O executable: invalid slice bounds")
            if any(offset < end and start < offset + size for start, end in ranges):
                raise ValueError("Invalid universal Mach-O executable: overlapping slices")
            architecture = thin_architecture(offset, size)
            if (cpu_type, cpu_subtype) != (architecture["cpuType"], architecture["cpuSubtype"]):
                raise ValueError("Universal Mach-O architecture table disagrees with its slice header")
            if architecture in architectures:
                raise ValueError("Invalid universal Mach-O executable: duplicate architecture")
            architectures.append(architecture)
            ranges.append((offset, offset + size))
        return sorted(architectures, key=lambda item: (item["cpuType"], item["cpuSubtype"]))


def inspect_bundle(path: Path, configuration: str) -> dict:
    """Count logical file bytes, once per path. Never follow links outside a bundle."""
    info_path = path / "Info.plist"
    if not info_path.is_file():
        raise ValueError(f"Incomplete app bundle: {info_path} is missing")
    with info_path.open("rb") as stream:
        info = plistlib.load(stream)
    if not isinstance(info, dict):
        raise ValueError("App Info.plist must be a dictionary")
    executable_name = info.get("CFBundleExecutable")
    if not isinstance(executable_name, str) or Path(executable_name).name != executable_name:
        raise ValueError("CFBundleExecutable must identify one bundle file")
    executable = path / executable_name
    if not executable.is_file() or executable.is_symlink() or executable.stat().st_size == 0:
        raise ValueError("Incomplete app bundle: executable is missing, empty, or a link")
    stamped = info.get("WhereConfiguration")
    if stamped != configuration:
        raise ValueError(f"Expected stamped configuration {configuration}, found {stamped!r}")
    for field in ("CFBundleIdentifier", "DTPlatformName", "DTSDKBuild"):
        if not isinstance(info.get(field), str) or not info[field]:
            raise ValueError(f"Missing build identity field: {field}")
    total = 0
    file_count = 0
    link_count = 0
    standalone_catalog_file_bytes = 0
    frameworks_bytes = 0
    for entry in path.rglob("*"):
        details = entry.lstat()
        if stat.S_ISLNK(details.st_mode):
            link_count += 1
            continue
        if not stat.S_ISREG(details.st_mode):
            continue
        total += details.st_size
        file_count += 1
        if entry.name.endswith(".porthole.json"):
            standalone_catalog_file_bytes += details.st_size
        if "Frameworks" in entry.relative_to(path).parts:
            frameworks_bytes += details.st_size
    return {
        "status": "measured",
        "path": str(path.resolve()),
        "configuration": stamped,
        "bundleIdentifier": info["CFBundleIdentifier"],
        "platform": info["DTPlatformName"],
        "sdkBuild": info["DTSDKBuild"],
        "xcodeBuild": info.get("DTXcodeBuild"),
        "buildIdentity": info.get("WhereGitSHA", "unknown"),
        "sourceStatus": info.get("WhereGitStatus", "unknown"),
        "optimization": info.get("WhereSwiftOptimizationLevel", "unknown"),
        "compilationMode": info.get("WhereSwiftCompilationMode", "unknown"),
        "architectures": executable_architectures(executable),
        "logicalBytes": total,
        "executableBytes": executable.stat().st_size,
        "embeddedFrameworkBytes": frameworks_bytes,
        "standalonePortholeCatalogFileBytes": standalone_catalog_file_bytes,
        # Keep the version-one key as an alias; it never measured embedded Swift constants.
        "portholeCatalogBytes": standalone_catalog_file_bytes,
        "catalogSizeDefinition": CATALOG_SIZE_DEFINITION,
        "regularFiles": file_count,
        "symbolicLinksExcluded": link_count,
    }


def bundle_result(path: Path | None, configuration: str) -> dict:
    if path is None:
        return {"status": "missing", "reason": "No completed app bundle was supplied."}
    try:
        return inspect_bundle(path, configuration)
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        return {"status": "rejected", "path": str(path), "reason": str(error)}


def compare_bundles(current: dict, baseline: dict) -> dict:
    if current["status"] != "measured" or baseline["status"] != "measured":
        return {"status": "missing", "reason": "Two complete, comparable app bundles are required."}
    if not current.get("architectures") or not baseline.get("architectures"):
        return {"status": "rejected", "reason": "Executable architecture information is missing."}
    fields = ("configuration", "bundleIdentifier", "platform", "sdkBuild", "xcodeBuild", "optimization", "compilationMode", "architectures")
    # Equal missing stamps do not establish comparable builds. Source revisions
    # must be known, but differ legitimately between the baseline and current app.
    identity_fields = fields[:-1] + ("buildIdentity",)
    unavailable = [key for key in identity_fields
                   if any(not isinstance(value, str) or not value.strip() or value.strip().lower() == "unknown"
                          for value in (current.get(key), baseline.get(key)))]
    if unavailable:
        return {"status": "rejected", "reason": "Build identity metadata is missing or unknown: " + ", ".join(unavailable)}
    mismatched = [key for key in fields if current[key] != baseline[key]]
    if mismatched:
        return {"status": "rejected", "reason": "Build metadata differs: " + ", ".join(mismatched)}
    return {
        "status": "measured",
        "logicalByteDifference": current["logicalBytes"] - baseline["logicalBytes"],
        "executableByteDifference": current["executableBytes"] - baseline["executableBytes"],
        "note": "This is a build-to-build difference. The caller must establish that only Porthole changed.",
    }


def read_runtime_samples(path: Path | None) -> list[dict]:
    if path is None:
        return []
    document = json.loads(path.read_text())
    if not isinstance(document, dict) or document.get("version") != 1 or not isinstance(document.get("samples"), list):
        raise ValueError("Runtime samples require version 1 and a samples array")
    samples = document["samples"]
    for sample in samples:
        if not isinstance(sample, dict):
            raise ValueError("Each runtime sample must be an object")
        if sample.get("configuration") not in CONFIGURATIONS or sample.get("metric") not in METRICS:
            raise ValueError("Runtime sample has an unknown configuration or metric")
        if sample.get("variant") not in ("baseline", "portholeDisabled", "portholeEnabled"):
            raise ValueError("Runtime sample must identify baseline, portholeDisabled, or portholeEnabled")
        for field in ("platform", "hardware", "osVersion", "buildIdentity", "method", "recordedAt", "evidencePath"):
            if not isinstance(sample.get(field), str) or not sample[field].strip():
                raise ValueError(f"Runtime sample needs provenance field {field}")
        recorded = datetime.fromisoformat(sample["recordedAt"].replace("Z", "+00:00"))
        if recorded.tzinfo is None:
            raise ValueError("Runtime sample recordedAt requires a time zone")
        value = sample.get("value")
        if isinstance(value, bool) or not isinstance(value, (float, int)) or not math.isfinite(value) or value <= 0:
            raise ValueError("Runtime sample values must be finite and positive")
        if sample["metric"] == "residentBytes" and int(value) != value:
            raise ValueError("Resident byte measurements must be whole numbers")
        if sample["metric"] == "launchMilliseconds" and not isinstance(sample.get("coldStart"), bool):
            raise ValueError("Launch samples must identify coldStart")
        evidence = Path(sample["evidencePath"])
        if not evidence.is_absolute():
            evidence = path.parent / evidence
        if not evidence.exists():
            raise ValueError(f"Runtime evidence does not exist: {evidence}")
        sample["evidencePath"] = str(evidence.resolve())
    return samples


def summarize_runtime(samples: list[dict], configuration: str) -> dict:
    groups: dict[tuple, list[dict]] = {}
    grouping = ("metric", "variant", "platform", "hardware", "osVersion", "buildIdentity", "method", "coldStart")
    for sample in samples:
        if sample["configuration"] != configuration:
            continue
        key = tuple(sample.get(field) for field in grouping)
        groups.setdefault(key, []).append(sample)
    summaries = []
    for key, group in sorted(groups.items(), key=lambda item: str(item[0])):
        values = sorted(sample["value"] for sample in group)
        summaries.append({
            **dict(zip(grouping, key)),
            "count": len(values),
            "median": statistics.median(values),
            "minimum": values[0],
            "maximum": values[-1],
            "samples": group,
        })
    present = {item["metric"] for item in summaries}
    return {
        "status": "recorded" if set(METRICS) <= present else "incomplete",
        "missingMetrics": [metric for metric in METRICS if metric not in present],
        "groups": summaries,
        "note": "Runtime samples are supplied observations, not measurements performed by this tool. No acceptance threshold is inferred.",
    }


def build_report(bundles: dict[str, Path], baselines: dict[str, Path], samples: list[dict]) -> dict:
    configurations = {}
    for configuration in CONFIGURATIONS:
        current = bundle_result(bundles.get(configuration), configuration)
        baseline = bundle_result(baselines.get(configuration), configuration)
        configurations[configuration] = {
            "bundle": current,
            "baseline": baseline,
            "difference": compare_bundles(current, baseline),
            "runtime": summarize_runtime(samples, configuration),
        }
    return {
        "version": 1,
        "recordedAt": datetime.now(timezone.utc).isoformat(),
        "acceptance": "notEvaluated",
        "configurations": configurations,
        "sizeDefinition": "Sum of regular-file logical bytes in the supplied .app; excludes symlinks. This is not App Store download size or unique APFS physical storage.",
    }


def assignments(values: list[str]) -> dict[str, Path]:
    result = {}
    for value in values:
        configuration, separator, path = value.partition("=")
        if separator != "=" or configuration not in CONFIGURATIONS or not path:
            raise ValueError("Bundle arguments use Debug=/path, Beta=/path, or Release=/path")
        if configuration in result:
            raise ValueError(f"Duplicate bundle argument for {configuration}")
        result[configuration] = Path(path)
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle", action="append", default=[], metavar="CONFIGURATION=APP")
    parser.add_argument("--baseline", action="append", default=[], metavar="CONFIGURATION=APP")
    parser.add_argument("--runtime-samples", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        report = build_report(assignments(args.bundle), assignments(args.baseline), read_runtime_samples(args.runtime_samples))
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2) + "\n")
    except (OSError, ValueError, TypeError) as error:
        parser.error(str(error))
    # A successful report write does not mean the product passed acceptance.
    print(f"Wrote {args.output}. Acceptance was not evaluated.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
