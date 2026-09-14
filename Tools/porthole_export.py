#!/usr/bin/env python3
"""Generate the app target's catalog before project generation and before each compilation."""
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import subprocess


CONTROL_PLANE_REASON = (
    "Native debugger control plane: automatic invocation could bypass execution, "
    "approval, or credential ownership. Use the registered Porthole capabilities."
)
CREDENTIAL_FILE = re.compile(r"Credential|Keychain|TLSIdentity|Enrollment|RemotePairing|Certificates")


def target_sources(root: Path, target: dict, suffixes: set[str]) -> list[Path]:
    """Honor explicit source roots and exclusions when a target shares an ancestor."""
    directory = root / target["path"]
    excluded = [directory / path for path in target.get("exclude", [])]
    selected = target.get("sources")
    roots = [directory / path for path in selected] if selected is not None else [directory]
    files: set[Path] = set()
    for source in roots:
        candidates = [source] if source.is_file() else source.rglob("*")
        for path in candidates:
            if path.suffix in suffixes and not any(path == item or item in path.parents for item in excluded):
                files.add(path)
    return sorted(files)


def control_plane_inventory(root: Path, package: dict, local_packages: dict[str, dict]) -> dict:
    """Inventory every reachable native debugger module without compiling access to it."""
    targets = {target["name"]: (root, target) for target in package["targets"]}
    local_products: dict[tuple[str, str], list[str]] = {}
    for identity, local in local_packages.items():
        directory = Path(local["directory"])
        for target in local["package"]["targets"]:
            targets[target["name"]] = (directory, target)
        for product in local["package"]["products"]:
            local_products[(identity.lower(), product["name"])] = product["targets"]

    visited: set[str] = set()
    queue = ["WhereUI", "WhereIntents", "WhereCrashReporting"]
    while queue:
        name = queue.pop()
        if name in visited or name not in targets:
            continue
        visited.add(name)
        _, target = targets[name]
        for dependency in target.get("dependencies", []):
            if "target" in dependency:
                queue.append(dependency["target"][0])
            elif "byName" in dependency:
                queue.append(dependency["byName"][0])
            elif "product" in dependency:
                product, identity = dependency["product"][:2]
                queue.extend(local_products.get(((identity or "").lower(), product), []))

    modules = []
    for name in sorted(visited):
        if not name.startswith(("Porthole", "CQuickJS")):
            continue
        directory, target = targets[name]
        files = target_sources(directory, target, {".swift", ".c", ".h"})
        sources = []
        excluded = []
        for path in files:
            reason = None
            if CREDENTIAL_FILE.search(path.name):
                reason = "Credential and enrollment machinery is excluded from automatic source and API exposure."
            elif path.suffix != ".swift":
                reason = ("Third-party interpreter internals are outside automatic exposure."
                          if "vendor" in path.parts else "The native interpreter bridge is not a Swift API; use the console capability.")
            if reason:
                excluded.append({"path": str(path), "reason": reason})
            else:
                sources.append(str(path))
        modules.append({"name": name, "reason": CONTROL_PLANE_REASON,
                        "sources": sources, "excludedFiles": excluded})
    return {"modules": modules}


def module_sources(root: Path, package: dict) -> list[Path]:
    """Use the manifest's opted-in targets; no parallel target list can drift."""
    sources: list[Path] = []
    for target in package["targets"]:
        if not any((plugin.get("plugin") or [None])[0] == "PortholeBuildPlugin"
                   for plugin in target.get("pluginUsages", [])):
            continue
        sources.extend(target_sources(root, target, {".swift"}))
    return sorted(sources)


def validate_installation(package: dict, installers: dict[str, str]) -> None:
    """Stop the build if a newly exported module has no composition-root installer."""
    expected = {target["name"] for target in package["targets"]
                if any((plugin.get("plugin") or [None])[0] == "PortholeBuildPlugin"
                       for plugin in target.get("pluginUsages", []))}
    installed = set()
    for module, source in installers.items():
        # Require executable call-shaped lines, not mentions in prose comments.
        for match in re.finditer(r"^\s*try await (?:(\w+)\.)?PortholeGeneratedModule\.install\(", source, re.MULTILINE):
            installed.add(match.group(1) or module)
    missing = expected - installed
    if missing:
        raise ValueError("Porthole exports modules without a runtime installer: "
                         + ", ".join(sorted(missing))
                         + ". Add their generated install calls to the application composition root.")


def generate(root: Path) -> None:
    env = os.environ.copy()
    # Xcode's iOS SDKROOT must not turn the build-tool executable into an iOS binary.
    env.pop("SDKROOT", None)
    env.pop("SWIFT_EXEC", None)
    env["PORTHOLE_BUILD_CONFIGURATION"] = os.environ.get("CONFIGURATION", "project-generation")
    env["PORTHOLE_TOOLCHAIN_ID"] = subprocess.check_output(["xcrun", "swiftc", "--version"], env=env, text=True, stderr=subprocess.STDOUT).strip()
    package = json.loads(subprocess.check_output(["swift", "package", "dump-package"], cwd=root, env=env))
    validate_installation(package, {
        "WhereUI": (root / "Where/WhereUI/Sources/Porthole/WherePortholeBindings.swift").read_text(),
        "Where": (root / "Where/Where/Sources/RegularApplicationRuntime.swift").read_text(),
    })
    # Tuist replaces Derived during generation. Keep app compiler inputs outside it.
    output = root / ".generated" / "Porthole" / "Where"
    local_packages = {}
    for dependency in package["dependencies"]:
        for local in dependency.get("fileSystem", []):
            directory = Path(local["path"])
            local_packages[local["identity"]] = {
                "directory": str(directory),
                "package": json.loads(subprocess.check_output(
                    ["swift", "package", "dump-package"], cwd=directory, env=env)),
            }
    output.mkdir(parents=True, exist_ok=True)
    inventory_path = output / "native-inventory.json"
    inventory_path.write_text(json.dumps(control_plane_inventory(root, package, local_packages), indent=2) + "\n")
    command = ["swift", "run", "--package-path", str(root / "Shared/Porthole/PortholeGenerator"),
               "PortholeGenerator", "--module", "Where", "--root", str(root),
               "--output", str(output / "PortholeGeneratedModule.swift"),
               "--catalog", str(output / "Where.porthole.json"),
               "--inventory-manifest", str(inventory_path)]
    for path in sorted((root / "Where/Where/Sources").rglob("*.swift")):
        command.extend(["--source", str(path)])
    for path in module_sources(root, package):
        command.extend(["--dependency-source", str(path)])
    subprocess.run(command, cwd=root, env=env, check=True)


if __name__ == "__main__":
    generate(Path(__file__).resolve().parent.parent)
