"""Execute prebuilt layout probes; never build or launch a production app."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess

MARKER = "VIEW_LAYOUT_AUDIT_COMPLETE"
IOS_RUNNERS = {
    "ViewLayoutAuditIOS": "com.stuff.layoutaudit.ios",
    "BroadwayCatalogLayoutAuditCompanion": "com.stuff.layoutaudit.broadwaycatalog",
    "WhereWidgetsLayoutAuditCompanion": "com.stuff.layoutaudit.wherewidgets",
    "WhereShareExtensionLayoutAuditCompanion": "com.stuff.layoutaudit.whereshareextension",
}
MAC_RUNNERS = {"LedgerLayoutAuditCompanion": "com.stuff.layoutaudit.ledger"}


def fingerprint(root):
    paths = {root / "Package.swift", root / "Package.resolved", root / "Project.swift"}
    for area in ("Shared", "Where", "Ledger"):
        paths.update(p for p in (root / area).rglob("*.swift") if "Sources" in p.parts and "Prototypes" not in p.parts)
    paths.update((root / "Tools/ViewLayoutAudit/Runner").rglob("*.swift"))
    paths.add(root / "Tools/ViewLayoutAudit/registrations.json")
    paths.add(root / "Tools/ViewLayoutAudit/platforms.json")
    digest = hashlib.sha256()
    for path in sorted(paths):
        digest.update(path.relative_to(root).as_posix().encode())
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def parse_output(output, payload):
    if "is implemented in both" in output:
        raise ValueError("Duplicate runtime classes invalidate the audit; inspect the package link graph")
    if output.splitlines().count(MARKER) != 1:
        raise ValueError("Expected exactly one completion marker; inspect runner logs")
    return json.loads(payload)


def execute(root, products, platform, configuration, output, simulator_args):
    output = output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    runners = MAC_RUNNERS if platform == "macOS" else IOS_RUNNERS
    device = None
    if platform == "iOSSimulator":
        device = subprocess.run([str(root / "simulator"), *simulator_args], cwd=root, check=True, text=True, capture_output=True, timeout=300).stdout.strip()
        if not device or "\n" in device:
            raise ValueError("Simulator command did not return one device identifier")
    reports = []
    for name, bundle_id in runners.items():
        bundle = products.resolve() / (name + ".app")
        if not bundle.is_dir():
            raise ValueError(f"Missing prebuilt audit app: {bundle}")
        environment = os.environ.copy()
        if platform == "macOS":
            payload = output / (name + ".json")
            command = [str(bundle / "Contents/MacOS" / name)]
            environment["VIEW_LAYOUT_AUDIT_OUTPUT"] = str(payload)
        else:
            subprocess.run(["xcrun", "simctl", "install", device, str(bundle)], check=True, timeout=120)
            container = subprocess.run(["xcrun", "simctl", "get_app_container", device, bundle_id, "data"], check=True, text=True, capture_output=True, timeout=30).stdout.strip()
            payload = Path(container) / "Documents/view-layout-report.json"
            environment["SIMCTL_CHILD_VIEW_LAYOUT_AUDIT_OUTPUT"] = str(payload)
            command = ["xcrun", "simctl", "launch", "--console", "--terminate-running-process", device, bundle_id]
        payload.unlink(missing_ok=True)
        log = output / (name + ".log")
        try:
            with log.open("w") as stream:
                completed = subprocess.run(command, cwd=root, env=environment, text=True, stdout=stream, stderr=subprocess.STDOUT, timeout=180)
            if completed.returncode:
                raise ValueError(f"Audit runner failed with status {completed.returncode}; see {log}")
            report = parse_output(log.read_text(), payload.read_text())
            (output / (name + ".json")).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
            reports.append(report)
        finally:
            if device:
                # Only our audit bundle. A completed process is already gone.
                subprocess.run(["xcrun", "simctl", "terminate", device, bundle_id], capture_output=True, timeout=30)
    report = {"build": reports[0]["build"], "samples": []}
    for part in reports:
        if part["build"] != report["build"]:
            raise ValueError("Audit companions have mismatched build identities")
        report["samples"].extend(part["samples"])
    report_path = output / "report.json"
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    identity = report["build"]
    commit = subprocess.run(["git", "rev-parse", "HEAD"], cwd=root, text=True, capture_output=True, check=True).stdout.strip()
    xcode = subprocess.run(["xcodebuild", "-version"], text=True, capture_output=True, check=True).stdout.split("Build version ")[-1].strip()
    expected = {"configuration": configuration, "platform": platform, "inputHash": fingerprint(root), "commit": commit, "xcode": xcode}
    for key, value in expected.items():
        if identity.get(key) != value:
            raise ValueError(f"Stale or mismatched audit product: {key}: {identity.get(key)!r}, expected {value!r}")
    return report_path
