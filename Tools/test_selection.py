"""Conservative, explainable selection of logical test bundles from Git changes."""

from __future__ import annotations

from dataclasses import dataclass
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess


GLOBAL_PATHS = {
    "Package.swift",
    "Package.resolved",
    "Project.swift",
    "Tuist.swift",
    ".swiftformat",
    ".mise.toml",
    ".xcode-version",
    "test",
    "simulator",
    "ide",
}
GLOBAL_DIRECTORIES = (".github/", ".circleci/", "Tuist/")
# These inputs generate ToolsSnapshotTests' HTML through the production Astro site.
# Other unowned tools conservatively select everything.
SITE_INPUTS = (
    "Tools/InstallerKit/Site/",
    "Tools/InstallerKit/installer_update_site.py",
    "Tools/InstallerKit/installer_site_data.py",
    "Tools/astro_site.py",
    "Tools/Tests/Fixtures/installer_update_fixtures.py",
    "Tools/Tests/Fixtures/installer_update_site_snapshots.py",
    "package.json",
    "package-lock.json",
)
SWIFT_TOKEN = re.compile(
    r'"""[\s\S]*?"""|"(?:\\.|[^"\\])*"|//[^\n]*|/\*[\s\S]*?\*/|[()\[\]{}]'
)
STRING = r'"(?:\\.|[^"\\])*"'


def _without_comments(text: str) -> str:
    return SWIFT_TOKEN.sub(
        lambda match: " " if match[0].startswith(("//", "/*")) else match[0], text
    )


def _end(text: str, start: int) -> int:
    stack = []
    pairs = {")": "(", "]": "[", "}": "{"}
    for match in SWIFT_TOKEN.finditer(text, start):
        token = match[0]
        if token in ("(", "[", "{"):
            stack.append(token)
        elif token in pairs:
            if not stack or stack.pop() != pairs[token]:
                raise ValueError("unbalanced Project.swift declaration")
            if not stack:
                return match.end()
    raise ValueError("unterminated Project.swift declaration")


def declarations(project: str) -> dict[str, str]:
    """Read whole literal target calls, without consuming the next declaration."""
    project = _without_comments(project)
    if re.search(r"\blet project = Project\(", project):
        array = re.search(r"targets:\s*addingGroupedLibraryTests\(to:\s*\[", project)
        if not array:
            raise ValueError("unsupported Project.swift target list")
        start = array.end() - 1
        end = _end(project, start)
        if not re.match(r"\s*\)\s*,", project[end:]):
            raise ValueError("unsupported Project.swift target list expression")
        project = project[start + 1 : end - 1]
        remaining = project
        while remaining.strip(" \t\r\n,"):
            remaining = remaining.lstrip(" \t\r\n,")
            call = re.match(r'(?:unitTests|\.target)\(\s*name:\s*"\w+"\s*,', remaining)
            if not call:
                raise ValueError(
                    "target list must contain literal unitTests/.target calls"
                )
            remaining = remaining[_end(remaining, remaining.index("(")) :]
    result = {}
    for match in re.finditer(
        r'(?:\bunitTests|\.target)\(\s*name:\s*"(\w+)"\s*,', project
    ):
        start = project.index("(", match.start())
        window = project[match.start() : _end(project, start)]
        # Target references have no product/sources; literal definitions do.
        if "sources:" not in window and "product:" not in window:
            raise ValueError(f"{match[1]} has no literal target sources")
        if match[1] in result:
            raise ValueError(f"duplicate target {match[1]}")
        result[match[1]] = window
    return result


def _array(window: str, field: str, *, required: bool = False) -> str:
    match = re.search(rf"\b{field}:\s*", window)
    if not match:
        if required:
            raise ValueError(f"missing {field}")
        return ""
    start = match.end()
    if window[start : start + 1] != "[":
        raise ValueError(f"{field} must be a literal array")
    end = _end(window, start)
    if not re.match(r"\s*[,)]", window[end:]):
        raise ValueError(f"unsupported {field} expression")
    return window[start + 1 : end - 1]


def _strings(array: str) -> list[str]:
    if re.sub(STRING, "", array).strip(" \t\r\n,"):
        raise ValueError("unsupported literal string array")
    values = [json.loads(match[0]) for match in re.finditer(STRING, array)]
    if any("\\" in value or ".." in PurePosixPath(value).parts for value in values):
        raise ValueError("unsupported interpolated or relative path")
    return values


def _roots(window: str) -> list[str]:
    sources = _strings(_array(window, "sources", required=True))
    if not sources:
        raise ValueError("empty target sources")
    resources = _array(window, "resources")
    resources = re.sub(rf"\.folderReference\(path:\s*({STRING})\)", r"\1", resources)
    return sources + _strings(resources)


def _dependencies(array: str) -> set[str]:
    pattern = r'\.(package|target)\((?:product|name):\s*"(\w+)"\)'
    if re.sub(pattern, "", array).strip(" \t\r\n,"):
        raise ValueError("unsupported target dependency expression")
    return {
        ("product:" if match[1] == "package" else "target:") + match[2]
        for match in re.finditer(pattern, array)
    }


def _owns(pattern: str, path: str) -> bool:
    # Select the enclosing directory for globs. This deliberately includes new
    # fixtures, deleted files, and snapshot references without filesystem globs.
    prefix = re.split(r"[*?\[]", pattern, maxsplit=1)[0]
    if prefix != pattern:
        prefix = prefix.rpartition("/")[0]
    prefix = prefix.rstrip("/")
    return path == prefix or path.startswith(prefix + "/")


@dataclass
class Graph:
    roots: dict[str, list[str]]
    dependencies: dict[str, set[str]]
    bundles: dict[str, str]
    host_tests: dict[str, str]

    @classmethod
    def read(cls, package: dict, project: str) -> "Graph":
        roots, dependencies, bundles, host_tests = {}, {}, {}, {}
        targets = package["targets"]
        names = {target["name"] for target in targets}
        for target in targets:
            node = "package:" + target["name"]
            path = target.get("path")
            if not path:
                raise ValueError(f"{node} needs an explicit package path")
            roots[node] = [path]
            dependencies[node] = set()
            for dependency in target.get("dependencies", []):
                kind = next(
                    (
                        key
                        for key in ("target", "byName", "product")
                        if key in dependency
                    ),
                    None,
                )
                if kind is None:
                    raise ValueError(f"unsupported package dependency in {node}")
                name = dependency[kind][0]
                prefix = (
                    "package:" if kind != "product" and name in names else "product:"
                )
                dependencies[node].add(prefix + name)
            if target.get("type") == "test":
                host_tests[target["name"]] = node
        for product in package.get("products", []):
            dependencies["product:" + product["name"]] = {
                "package:" + name for name in product["targets"]
            }
        # Some test fixtures omit products. The real dump always supplies them.
        if "products" not in package:
            for name in names:
                dependencies["product:" + name] = {"package:" + name}

        project = _without_comments(project)
        helper_dependencies = set()
        helper = re.search(
            r"func unitTests\([\s\S]*?\) -> (?:ProjectDescription\.)?Target\s*\{",
            project,
        )
        if not helper and re.search(r"\bunitTests\(\s*name:", project):
            raise ValueError("unsupported or missing unitTests helper")
        if helper:
            signature = helper[0]
            for field in ("resources", "extraPackageProducts", "scripts"):
                if re.search(rf"\b{field}:", signature) and not re.search(
                    rf"\b{field}:\s*(?:\[\w+\]|\w+)\s*=\s*\[\s*\]\s*[,)]",
                    signature,
                ):
                    raise ValueError(f"unsupported unitTests helper {field} default")
            start = helper.end() - 1
            body = project[start : _end(project, start)]
            for field in ("dependencies", "sources", "resources", "scripts"):
                if (
                    field == "dependencies" or re.search(rf"\b{field}:", signature)
                ) and not re.search(rf"\b{field}:\s*{field}\s*[,)]", body):
                    raise ValueError(f"unsupported unitTests helper {field} forwarding")
            match = re.search(
                r"var dependencies: \[TargetDependency\] = (\[[\s\S]*?\])", body
            )
            if not match:
                raise ValueError("unsupported unitTests helper dependencies")
            dependency_section = body[1 : body.index("return .target(")]
            known = re.compile(
                r"\s*var dependencies: \[TargetDependency\] = \[[\s\S]*?\]"
                r"\s*for product in extraPackageProducts\s*\{"
                r"\s*dependencies.append\(\.package\(product: product\)\)\s*\}\s*"
            )
            if not known.fullmatch(dependency_section):
                raise ValueError("unsupported unitTests helper dependency construction")
            array = match[1][1:-1].replace(".package(product: productDependency),", "")
            helper_dependencies = _dependencies(array)

        declared = declarations(project)
        for name, window in declared.items():
            node = "target:" + name
            try:
                roots[node] = _roots(window)
                dependencies[node] = _dependencies(_array(window, "dependencies"))
                if window.startswith("unitTests("):
                    product = re.search(r'productDependency:\s*"(\w+)"\s*[,)]', window)
                    if not product:
                        raise ValueError("missing literal productDependency")
                    dependencies[node] |= helper_dependencies | {
                        "product:" + product[1]
                    }
                    dependencies[node] |= {
                        "product:" + product
                        for product in _strings(_array(window, "extraPackageProducts"))
                    }
                if name.endswith("Tests"):
                    bundles[name] = node
            except ValueError as error:
                raise ValueError(f"{name}: {error}") from error
        if len(bundles) < 15:
            raise ValueError(f"only found {len(bundles)} test bundles")
        missing = {
            dependency
            for items in dependencies.values()
            for dependency in items
            if dependency.startswith("target:") and dependency not in dependencies
        }
        if missing:
            raise ValueError(f"missing target declarations: {sorted(missing)}")
        return cls(roots, dependencies, bundles, host_tests)

    def select(self, changed: list[str], *, fallback: str = "") -> dict:
        selected: dict[str, list[str]] = {}
        ignored, unowned = [], []
        reverse: dict[str, set[str]] = {}
        for node, dependencies in self.dependencies.items():
            for dependency in dependencies:
                reverse.setdefault(dependency, set()).add(node)
        all_tests = self.bundles | self.host_tests
        for path in sorted(set(changed)):
            if path in GLOBAL_PATHS or path.startswith(GLOBAL_DIRECTORIES):
                fallback = fallback or f"global test/build input: {path}"
                continue
            owners = {
                node
                for node, patterns in self.roots.items()
                if any(_owns(pattern, path) for pattern in patterns)
            }
            if any(
                path == entry or (entry.endswith("/") and path.startswith(entry))
                for entry in SITE_INPUTS
            ):
                if "ToolsSnapshotTests" not in self.bundles:
                    raise ValueError(
                        "generated site inputs have no ToolsSnapshotTests target"
                    )
                owners.add(self.bundles["ToolsSnapshotTests"])
            if not owners:
                parts = PurePosixPath(path).parts
                if PurePosixPath(path).suffix.lower() in {".md", ".markdown"} and not {
                    "resources",
                    "fixtures",
                    "__snapshots__",
                    "src",
                    "public",
                }.intersection(part.lower() for part in parts[:-1]):
                    ignored.append(path)
                else:
                    unowned.append(path)
                    fallback = fallback or f"unowned input: {path}"
                continue
            affected = set(owners)
            frontier = list(owners)
            while frontier:
                for dependent in reverse.get(frontier.pop(), ()):
                    if dependent not in affected:
                        affected.add(dependent)
                        frontier.append(dependent)
            reached = False
            for name, node in all_tests.items():
                if node in affected:
                    selected.setdefault(name, []).append(path)
                    reached = True
            if not reached:
                unowned.append(path)
                fallback = fallback or f"no test consumer for input: {path}"
        if fallback:
            selected = {name: [fallback] for name in sorted(all_tests)}
        unit = sorted(
            name for name in self.bundles if not name.endswith("SnapshotTests")
        )
        snapshots = sorted(set(self.bundles) - set(unit))
        return {
            "format_version": 1,
            "mode": "full" if fallback else "affected" if selected else "empty",
            "fallback_reason": fallback or None,
            "changed_paths": sorted(set(changed)),
            "selected": sorted(self.bundles.keys() & selected.keys()),
            "skipped": sorted(self.bundles.keys() - selected.keys()),
            "unit_bundles": unit,
            "snapshot_bundles": snapshots,
            "host_tests": sorted(self.host_tests.keys() & selected.keys()),
            "reasons": dict(sorted(selected.items())),
            "ignored_documentation": ignored,
            "unowned_paths": unowned,
            "independent_checks": [
                "architecture",
                "flyover command",
                "attribution",
                "backup upgrader",
            ],
        }


def git_changes(root: Path, base: str, head: str | None) -> tuple[list[str], dict, str]:
    def git(*arguments: str) -> bytes:
        return subprocess.run(
            ["git", *arguments], cwd=root, capture_output=True, check=True
        ).stdout

    comparison = {
        "base": base,
        "head": head or "HEAD",
        "includes_local_changes": head is None,
    }
    try:
        # Resolve refs before using them as diff arguments; never interpret a ref as a flag.
        base_sha = (
            git("rev-parse", "--verify", "--end-of-options", base + "^{commit}")
            .decode()
            .strip()
        )
        head_sha = (
            git(
                "rev-parse",
                "--verify",
                "--end-of-options",
                (head or "HEAD") + "^{commit}",
            )
            .decode()
            .strip()
        )
        merge_base = git("merge-base", base_sha, head_sha).decode().strip()
        comparison.update(
            base_commit=base_sha, head_commit=head_sha, merge_base=merge_base
        )
        arguments = (
            "diff",
            "--name-only",
            "-z",
            "--no-renames",
            "--no-ext-diff",
            "--no-textconv",
        )
        raw = git(*arguments, merge_base, head_sha, "--")
        if head is None:
            raw += git(*arguments, "HEAD", "--")
            raw += git("ls-files", "--others", "--exclude-standard", "-z")
        if raw and not raw.endswith(b"\0"):
            raise ValueError("incomplete Git paths")
        return (
            sorted({os.fsdecode(path) for path in raw.split(b"\0") if path}),
            comparison,
            "",
        )
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        return (
            [],
            comparison,
            f"Git comparison unavailable ({type(error).__name__}); run the full suite",
        )


def repository_selection(root: Path, base: str, head: str | None) -> dict:
    changed, comparison, fallback = git_changes(root, base, head)
    package = json.loads(
        subprocess.run(
            ["swift", "package", "dump-package"],
            cwd=root,
            capture_output=True,
            text=True,
            check=True,
        ).stdout
    )
    graph = Graph.read(package, (root / "Project.swift").read_text())
    report = graph.select(changed, fallback=fallback)
    report["comparison"] = comparison
    report["graph"] = "current checkout manifests (including local edits)"
    return report


def describe(report: dict) -> str:
    lines = [f"Selection: {report['mode']}"]
    if report["fallback_reason"]:
        lines.append(f"Reason: {report['fallback_reason']}")
    lines.append(
        f"Selected {len(report['selected'])} of {len(report['selected']) + len(report['skipped'])} iOS bundles:"
    )
    for name in report["selected"]:
        lines.append(f"  {name}")
        lines.extend(f"    {reason}" for reason in report["reasons"][name])
    lines.append(f"Skipped {len(report['skipped'])} iOS bundles:")
    lines.extend(f"  {name}" for name in report["skipped"])
    lines.append("Host tests: " + (", ".join(report["host_tests"]) or "none selected"))
    lines.append("Independent checks: " + ", ".join(report["independent_checks"]))
    lines.append(
        "This previews execution scope. Builds still compile the selected schemes."
    )
    return "\n".join(lines)
