#!/usr/bin/env python3
"""Check built Where app packaging without launching or modifying any product."""
from __future__ import annotations

import argparse
from collections import deque
import copy
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys

import porthole_macho_exports
import porthole_macho_symbols


FAMILY_STEMS = {
    "WhereModel": ["7WhereUI0A5ModelC", "7WhereUI10WhereModelC"],
    "CalendarDay": ["9WhereCore11CalendarDayV"],
    "Broadway.BTraits": ["12BroadwayCore7BTraitsV"],
    "Broadway.BContext": ["12BroadwayCore8BContextV"],
    "PortholeRegistry": ["15PortholeRuntime0A8RegistryC", "15PortholeRuntime16PortholeRegistryC"],
    "PortholeScopeToken": ["12PortholeCore0A10ScopeTokenV", "12PortholeCore18PortholeScopeTokenV"],
    "PortholeObjectReference": ["12PortholeCore0A15ObjectReferenceV", "12PortholeCore23PortholeObjectReferenceV"],
}
SYMBOL_FAMILIES = {prefix + "$s" + stem + suffix: family for family, stems in FAMILY_STEMS.items()
                   for stem in stems for prefix in ("", "_") for suffix in ("Ma", "Mn", "N")}
RESOURCE_PAYLOADS = {
    "LifecycleKitUI": ["en.lproj/Localizable.strings"],
    "RegionKit": ["regions.json", "en.lproj/Localizable.strings"],
    "WhereAssets": ["Assets.car"],
    "WhereCore": ["en.lproj/Localizable.strings", "en.lproj/Localizable.stringsdict"],
    "WhereIntents": ["en.lproj/Localizable.strings"],
    "WhereUI": ["AppIcons.json", "en.lproj/Localizable.strings", "en.lproj/Localizable.stringsdict"],
}
ACTION_IDS = {"DaysInRegionIntent", "DaysInRegionSnippetIntent", "LogDayIntent", "LogTripIntent",
              "RegionOnDateIntent", "TodayRegionsIntent"}
SHORTCUT_IDS = {"TodayRegionsIntent", "DaysInRegionIntent", "RegionOnDateIntent", "LogDayIntent"}
SYSTEM_PREFIXES = ("/System/Library/", "/usr/lib/", "/Library/Apple/System/Library/")
MAX_SMALL_FILE = 32 * 1024 * 1024


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def contained(path: Path, root: Path) -> Path:
    result = path.resolve(strict=True)
    if not result.is_relative_to(root):
        raise ValueError(f"Product path escapes its app: {path}")
    return result


def small_bytes(path: Path) -> bytes:
    if not path.is_file() or not 0 < path.stat().st_size <= MAX_SMALL_FILE:
        raise ValueError(f"Missing, empty, or oversized packaging file: {path}")
    return path.read_bytes()


def executable(bundle: Path, app: Path) -> Path:
    info = plistlib.loads(small_bytes(contained(bundle / "Info.plist", app)))
    name = info["CFBundleExecutable"]
    if not isinstance(name, str) or Path(name).name != name or name in {".", ".."}:
        raise ValueError(f"Invalid executable name in {bundle}")
    result = contained(bundle / name, app)
    if not result.is_file():
        raise ValueError(f"Missing executable in {bundle}")
    return result


def image_info(path: Path) -> dict:
    # otool reads load commands only. Do not use nm: it can hang on large Swift images.
    def run(flag):
        result = subprocess.run(["/usr/bin/otool", flag, str(path)], check=True,
                                capture_output=True, text=True, timeout=30)
        if len(result.stdout) > 8 * 1024 * 1024:
            raise ValueError("Unexpectedly large Mach-O load-command output")
        return result.stdout.splitlines()

    dependencies = [line.strip().split(" (compatibility version", 1)[0]
                    for line in run("-L")[1:] if line.strip()]
    commands, rpaths = run("-l"), []
    for index, line in enumerate(commands):
        if line.strip() == "cmd LC_RPATH":
            match = re.fullmatch(r"\s*path (.+) \(offset \d+\)", commands[index + 2])
            if match is None:
                raise ValueError(f"Cannot decode LC_RPATH in {path}")
            rpaths.append(match[1])
    return {"dependencies": dependencies, "rpaths": rpaths}


def build_output_runpath(app: Path, configuration: str, sdk: str) -> Path | None:
    """Only this verified product layout identifies Xcode's sibling build outputs."""
    product = app.parent
    if (app.name == "Where.app" and product.name == configuration + "-" + sdk
            and product.parent.name == "Products" and product.parent.parent.name == "Build"):
        return product / "PackageFrameworks"
    return None


def loaded_images(app: Path, host: Path, cache: dict, excluded_build_runpath: Path | None,
                  exclusions: dict[Path, set[str]]) -> list[Path]:
    def expand(value, loader):
        for token, base in [("@loader_path", loader.parent), ("@executable_path", host.parent)]:
            if value == token or value.startswith(token + "/"):
                return base / value[len(token):].lstrip("/")
        return Path(value)

    queue, seen = deque([(host, ())]), set()
    while queue:
        image, inherited = queue.popleft()
        if image in seen:
            continue
        seen.add(image)
        if len(seen) > 256:
            raise ValueError("More than 256 application images")
        if image not in cache:
            cache[image] = image_info(image)
        info = cache[image]
        # Inspect the relocatable app, not dyld's search inside this Mac build directory.
        # Never use sibling build products to satisfy an absent packaged dependency.
        local_rpaths = []
        for value in info["rpaths"]:
            if excluded_build_runpath is not None and value == str(excluded_build_runpath):
                exclusions.setdefault(image, set()).add(value)
            else:
                local_rpaths.append(expand(value, image))
        rpaths = tuple(local_rpaths) + inherited
        for dependency in info["dependencies"]:
            if dependency.startswith(SYSTEM_PREFIXES):
                continue
            candidates = ([base / dependency[len("@rpath/"):] for base in rpaths]
                          if dependency.startswith("@rpath/") else [expand(dependency, image)])
            resolved = next((candidate.resolve() for candidate in candidates if candidate.is_file()), None)
            if resolved is None or not resolved.is_relative_to(app):
                raise ValueError(f"Unresolved or outside-app dependency: {image}: {dependency}")
            if resolved != image:
                queue.append((resolved, rpaths))
    return sorted(seen)


def metadata_symbols(path: Path) -> list[dict]:
    matches = {}
    for symbol in porthole_macho_symbols.external_definitions(path):
        if symbol.name not in SYMBOL_FAMILIES:
            continue
        if symbol.indirect_target is not None:
            raise ValueError(f"Representative metadata is an indirect alias: {symbol.name}")
        if symbol.symbol_type != porthole_macho_symbols.N_SECT:
            raise ValueError(f"Representative metadata is not a section definition: {symbol.name}")
        matches[symbol.name] = {"family": SYMBOL_FAMILIES[symbol.name], "symbol": symbol.name, "weak": symbol.weak}
    for exported in porthole_macho_exports.selected_exports(path, SYMBOL_FAMILIES):
        if exported.flags & ~0x04:
            raise ValueError(f"Representative metadata is not a direct regular export: {exported.name}")
        old = matches.get(exported.name)
        if old is not None and old["weak"] != exported.weak:
            raise ValueError(f"Symbol table and export trie disagree on weak metadata: {exported.name}")
        matches[exported.name] = {"family": SYMBOL_FAMILIES[exported.name], "symbol": exported.name, "weak": exported.weak}
    return sorted(matches.values(), key=lambda item: item["symbol"])


def resource_inventory(bundle: Path, app: Path) -> dict:
    files = {}
    for path in bundle.rglob("*"):
        if path.is_symlink():
            raise ValueError(f"Unexpected resource symlink: {path}")
        if path.is_file():
            contained(path, app)
            if len(files) >= 4096 or path.stat().st_size > MAX_SMALL_FILE:
                raise ValueError(f"Resource inventory exceeds inspection limits: {bundle}")
            files[str(path.relative_to(bundle))] = digest(path)
    return dict(sorted(files.items()))


def check_resources(hosts: dict, app: Path, repository: Path) -> dict:
    manifests = {"RegionKit": ("regions.json", repository / "Where/RegionKit/Sources/Resources/regions.json"),
                 "WhereUI": ("AppIcons.json", repository / "Where/WhereUI/Sources/Resources/AppIcons.json")}
    result, originals = {}, {}
    for host_name, host in hosts.items():
        result[host_name] = {}
        for module, payloads in RESOURCE_PAYLOADS.items():
            bundle = contained(host / f"Stuff_{module}.bundle", app)
            info = plistlib.loads(small_bytes(bundle / "Info.plist"))
            if info.get("CFBundlePackageType") != "BNDL" or info.get("CFBundleIdentifier") != f"stuff.{module}.resources":
                raise ValueError(f"Wrong resource bundle identity: {bundle}")
            expected = list(payloads)
            if module in manifests:
                name, source = manifests[module]
                value = json.loads(small_bytes(bundle / name))
                if value != json.loads(small_bytes(source)):
                    raise ValueError(f"Bundled {module} manifest differs from its source")
                if module == "RegionKit":
                    for region in value:
                        if not isinstance(region, dict):
                            raise ValueError("Invalid region manifest entry")
                        file = region.get("geometry", {}).get("file")
                        if file is not None:
                            if not isinstance(file, str) or Path(file).name != file:
                                raise ValueError("Region geometry must name a direct bundle file")
                            expected.append(file)
            for name in expected:
                data = small_bytes(contained(bundle / name, app))
                if name.endswith((".strings", ".stringsdict")):
                    if not isinstance(plistlib.loads(data), dict):
                        raise ValueError(f"Invalid localized resource: {bundle / name}")
            inventory = resource_inventory(bundle, app)
            if host_name == "app":
                originals[module] = inventory
            elif inventory != originals[module]:
                raise ValueError(f"{host_name} {module} resources differ from the app copy")
            # Assets.car includes compiler timestamps. Preserve raw and per-host equality,
            # but do not claim opaque compiled bytes are comparable across separate builds.
            opaque = ["Assets.car"] if module == "WhereAssets" else []
            comparable = {name: "<opaque compiled asset>" if name in opaque else value for name, value in inventory.items()}
            result[host_name][module] = {
                "files": len(inventory), "sha256": hashlib.sha256(json.dumps(inventory, sort_keys=True).encode()).hexdigest(),
                "crossBuildSHA256": hashlib.sha256(json.dumps(comparable, sort_keys=True).encode()).hexdigest(),
                "opaqueCompiledFiles": opaque,
            }
    return result


def check_intents(app: Path, hosts: dict, frameworks: list[Path]) -> dict:
    for host in list(hosts.values())[1:] + frameworks:
        if any(host.rglob("Metadata.appintents")):
            raise ValueError(f"Unexpected App Intents metadata outside the app: {host}")
    path = contained(app / "Metadata.appintents/extract.actionsdata", app)
    value = json.loads(small_bytes(path))
    for key, identifiers in [("actions", ACTION_IDS), ("entities", {"RegionEntity"}), ("queries", {"RegionEntityQuery"})]:
        members = value[key]
        if not isinstance(members, dict) or set(members) != identifiers:
            raise ValueError(f"Unexpected App Intents {key}")
        for name, member in members.items():
            if not isinstance(member, dict) or member.get("fullyQualifiedIdentifier" if key == "queries" else "fullyQualifiedTypeName") != "WhereIntents." + name:
                raise ValueError(f"Unexpected App Intents type owner: {name}")
    shortcuts = value["autoShortcuts"]
    if not isinstance(shortcuts, list) or len(shortcuts) != 4 or any(not isinstance(item, dict) for item in shortcuts) or {item["actionIdentifier"] for item in shortcuts} != SHORTCUT_IDS:
        raise ValueError("Unexpected app shortcut routes")
    normalized = copy.deepcopy(value)
    # The pinned extractor reorders accepted types for Year parameters. No other array is reordered.
    for name in ("DaysInRegionIntent", "DaysInRegionSnippetIntent"):
        for parameter in normalized["actions"][name]["parameters"]:
            if not isinstance(parameter, dict):
                raise ValueError("Invalid App Intents parameter")
            if parameter.get("name") == "year":
                parameter["resolvableInputTypes"] = sorted(parameter["resolvableInputTypes"], key=lambda item: json.dumps(item, sort_keys=True))
    return {"sha256": digest(path), "semanticSHA256": hashlib.sha256(json.dumps(normalized, sort_keys=True).encode()).hexdigest(),
            "actions": sorted(ACTION_IDS), "shortcuts": sorted(SHORTCUT_IDS), "entities": ["RegionEntity"], "queries": ["RegionEntityQuery"]}


def inspect(app: Path, repository: Path, configuration: str, sdk: str) -> dict:
    app = app.resolve(strict=True)
    info = plistlib.loads(small_bytes(app / "Info.plist"))
    if info.get("WhereConfiguration") != configuration or info.get("DTPlatformName") != sdk:
        raise ValueError("App configuration/platform does not match this compiler pair")
    hosts = {"app": app, **{path.name: path for path in sorted((app / "PlugIns").glob("*.appex"))}}
    if set(hosts) != {"app", "WhereWidgets.appex", "WhereShareExtension.appex"}:
        raise ValueError("Unexpected Where app/extension host set")
    frameworks = sorted(app.rglob("*.framework"))
    for name in ("WhereApplicationSupport", "PortholeCertificates"):
        matches = [path for path in frameworks if path.name == name + ".framework"]
        if matches != [app / "Frameworks" / (name + ".framework")]:
            raise ValueError(f"Expected one app-only embedded {name} framework")
    support = executable(app / "Frameworks/WhereApplicationSupport.framework", app)
    certificate = executable(app / "Frameworks/PortholeCertificates.framework", app)
    cache, symbols, host_reports, exclusions = {}, {}, {}, {}
    excluded_build_runpath = build_output_runpath(app, configuration, sdk)
    for name, host in hosts.items():
        images = loaded_images(app, executable(host, app), cache, excluded_build_runpath, exclusions)
        if support not in images or certificate not in images:
            raise ValueError(f"{name} does not load both shared application frameworks")
        families = set()
        for image in images:
            if image not in symbols:
                symbols[image] = metadata_symbols(image)
            for item in symbols[image]:
                if image != support:
                    raise ValueError(f"{name}: {item['family']} metadata is outside the shared image")
                families.add(item["family"])
        if families != set(FAMILY_STEMS):
            raise ValueError(f"{name}: missing representative metadata families: {sorted(set(FAMILY_STEMS) - families)}")
        host_reports[name] = {"images": [str(path.relative_to(app)) for path in images], "metadataFamilies": sorted(families)}
    if any(app.rglob("*.porthole.json")):
        raise ValueError("Redundant standalone Porthole catalog resource remains")
    return {"status": "passed", "configuration": configuration, "sdk": sdk, "app": str(app),
            "bundleIdentifier": info["CFBundleIdentifier"], "hosts": host_reports,
            "excludedBuildRunpaths": {str(path.relative_to(app)): sorted(values) for path, values in sorted(exclusions.items())},
            "images": {str(path.relative_to(app)): {"sha256": digest(path), "metadata": symbols[path]} for path in sorted(symbols)},
            "resources": check_resources(hosts, app, repository), "appIntents": check_intents(app, hosts, frameworks),
            "limits": ["Relocatable app closure only; excludes the exact sibling PackageFrameworks runpath for verified Build/Products/configuration-sdk inputs.",
                       "Does not model in-place dyld search in a Mac build directory; no process is launched.",
                       "Samples seven metadata families, not every application symbol.",
                       "Does not qualify bundle APIs at runtime, widget/share flows, Siri/Shortcuts execution, signing, or App Review.",
                       "App Intents NLU timestamps and asset-catalog internals are not decoded.",
                       "Cross-build resource comparison omits WhereAssets/Assets.car payload bytes; source manifests, required paths, and within-product copies remain checked."]}


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--repository", type=Path, required=True)
    parser.add_argument("--configuration", choices=["Debug", "Beta", "Release"], required=True)
    parser.add_argument("--sdk", choices=["iphoneos", "iphonesimulator"], required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    if args.output.exists():
        parser.error("Use a new output path to preserve prior packaging evidence")
    try:
        report = inspect(args.app, args.repository, args.configuration, args.sdk)
    except (OSError, ValueError, KeyError, TypeError, IndexError, subprocess.SubprocessError) as error:
        report = {"status": "failed", "error": str(error)}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("x") as output:
        output.write(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"status": report["status"], "report": str(args.output)}))
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    sys.exit(main())
