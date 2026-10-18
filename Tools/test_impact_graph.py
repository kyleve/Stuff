"""Repository input ownership around XcodeSelectiveTesting's exported target graph."""

import hashlib
import json
from pathlib import Path
import re


VERSION = 1
SELECTOR_VERSION = "0.15.1"
SELECTOR_SHA256 = "8ecf68886e84ced93c2eafa59116f0c700e5cdeb322f273aa949bf3b6dcef1de"
GLOBAL_FILES = {
    "Package.swift", "Package.resolved", "Project.swift", "Tuist.swift", ".mise.toml",
    ".xcode-build-version", "test", "ide", "simulator", ".gitattributes",
}
GLOBAL_PREFIXES = (".circleci/", ".github/", "Tools/TestImpact/", "Tools/test_impact")
BROAD_PREFIXES = ("Shared/SnapshotKit/", "Shared/SnapshotKitTesting/", "Shared/Broadway/",
                  "Shared/Periscope/PeriscopeMacros/", "Shared/TestHostSupport/")


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def global_input(path):
    return path in GLOBAL_FILES or path.startswith(GLOBAL_PREFIXES)


def documentation(path):
    # No executable examples, app-rendered documents, or arbitrary Markdown directories.
    return Path(path).name in {"README.md", "AGENTS.md", "TODOs.md", "INBOX.md", "MODULE_AUDIT.md"}


def broad_input(path):
    return path.startswith(BROAD_PREFIXES) or any(
        name in Path(path).stem for name in ("Stylesheet", "Environment", "Theme")
    )


def target_graph(dot, known):
    """Read the pinned upstream DOT export, rejecting ambiguous or missing local edges."""
    graph = {name: [] for name in known}
    rows = 0
    for line in dot.splitlines():
        if "->" not in line:
            continue
        match = re.fullmatch(r'\s*"([^"\n]+)" -> \{(.*)\}\s*', line)
        if not match:
            raise ValueError("unsupported XcodeSelectiveTesting graph row")
        source = match[1].split(":")
        if len(source) != 2 or source[0] != "Stuff" or source[1] not in known:
            raise ValueError("unknown or ambiguous selector target: " + match[1])
        dependencies = []
        for name in re.findall(r'"([^"\n]+)"', match[2]):
            parts = name.split(":")
            if len(parts) != 2 or parts[0] != "Stuff" or parts[1] not in known:
                raise ValueError("unknown selector dependency: " + name)
            dependencies.append(parts[1])
        graph[source[1]] = sorted(set(dependencies))
        rows += 1
    if not rows:
        raise ValueError("selector exported no dependency edges")
    return graph


def closure(graph, roots):
    seen = set(roots)
    todo = list(roots)
    while todo:
        for dependency in graph.get(todo.pop(), []):
            if dependency not in seen:
                seen.add(dependency)
                todo.append(dependency)
    return seen


def catalog(root, tuist, package, dot, tracked):
    root = Path(root).resolve()
    projects = tuist["projects"]
    if not isinstance(projects, list) or len(projects) != 2:
        raise ValueError("expected one generated Tuist project")
    project = projects[1]
    targets = project["targets"]
    packages = {target["name"]: target for target in package["targets"]}
    known = set(targets) | set(packages)
    graph = target_graph(dot, known)
    inputs = {name: set() for name in known}
    macro_targets = set()

    def relative(path):
        return str(Path(path).relative_to(root))

    for name, target in targets.items():
        for source in target.get("sources", []):
            inputs[name].add(relative(source["path"]))
        # Tuist resource groups can nest file records. Only tracked paths are inputs.
        resource_text = json.dumps(target.get("resources", {}))
        for path in tracked:
            if str(root / path) in resource_text:
                inputs[name].add(path)
        expected = set()
        for dependency in target.get("dependencies", []):
            if "target" in dependency:
                expected.add(dependency["target"]["name"])
            elif "package" in dependency and dependency["package"]["product"] in known:
                expected.add(dependency["package"]["product"])
        if not expected <= set(graph[name]):
            raise ValueError(f"selector omits declared local dependencies of {name}")
    for name, target in packages.items():
        prefix = target.get("path", "Sources/" + name).rstrip("/") + "/"
        inputs[name].update(path for path in tracked if path.startswith(prefix))
        if target["type"] == "macro":
            macro_targets.add(name)
        expected = set()
        for dependency in target.get("dependencies", []):
            for kind in ("target", "byName"):
                if kind in dependency and dependency[kind][0] in known:
                    expected.add(dependency[kind][0])
        if not expected <= set(graph[name]):
            raise ValueError(f"selector omits declared package dependencies of {name}")

    # This build script has no declared Tuist inputs. Include the production generator,
    # its fixtures, and shipped artwork conservatively instead of guessing Swift edges.
    if "ToolsSnapshotTests" in inputs:
        inputs["ToolsSnapshotTests"].update(path for path in tracked if path.startswith((
            "Tools/InstallerKit/", "Tools/Tests/Fixtures/installer_update_site",
            "Where/Where/Resources/Assets.xcassets/", "Ledger/Ledger/Resources/",
        )))

    bundles = {}
    suites = {}
    for name, target in targets.items():
        if target.get("product") != "unit_tests":
            continue
        dependencies = closure(graph, [name])
        owned = sorted(set().union(*(inputs[item] for item in dependencies)))
        sources = sorted(set().union(*(inputs[item] for item in dependencies - macro_targets)))
        bundles[name] = {
            "inputs": owned, "sources": [path for path in sources if path.endswith(".swift")],
            "platform": "macOS" if "macOS" in target.get("deploymentTargets", {}) else "iOS",
        }
        if name.endswith("SnapshotTests"):
            for path in inputs[name]:
                if "/SnapshotTests/" in path and path.endswith(".swift"):
                    suites[name + "/" + Path(path).stem] = path
    if not bundles or not suites:
        raise ValueError("generated graph has no test inventory")
    # Reference images live beside test files, outside SPM source roots.
    for bundle, value in bundles.items():
        roots = {str(Path(path).parent) + "/" for suite, path in suites.items() if suite.split("/")[0] == bundle}
        value["inputs"] = sorted(set(value["inputs"]) | {
            path for path in tracked if any(path.startswith(prefix) for prefix in roots)
        })
    return {"bundles": bundles, "suites": dict(sorted(suites.items())), "graph": graph,
            "inventory": digest({"bundles": bundles, "suites": suites})}


def affected(catalogs, paths):
    names = set().union(*(set(item["bundles"]) for item in catalogs))
    selected = set()
    reasons = []
    for path in paths:
        if global_input(path):
            return names, ["global input: " + path]
        owners = {name for item in catalogs for name, bundle in item["bundles"].items() if path in bundle["inputs"]}
        if owners:
            selected.update(owners)
            reasons.append("input: " + path)
        elif not documentation(path):
            return names, ["unknown input: " + path]
    return selected, reasons
