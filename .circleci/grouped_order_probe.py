"""One-off CI experiment for serial Swift Testing suite-order isolation."""
from collections import Counter
from hashlib import sha256
from itertools import combinations
import json
import os
from pathlib import Path
import re
import subprocess
import sys

BASE = "GroupedLibraryTests"
VARIANTS = {101: "GroupedOrderAlphaTests", 307: "GroupedOrderBetaTests"}
BUNDLES = [BASE, *VARIANTS.values()]


def prepare(root, evidence):
    manifest = root / "Project.swift"
    text = manifest.read_text()
    members = re.search(r"groupedLibraryTestNames: Set<String> = \[(.*?)\]", text, re.S)
    if not members:
        raise ValueError("Grouped library membership declaration missing")
    files = []
    for member in re.findall(r'"(\w+)"', members[1]):
        body = re.search(r'        unitTests\(\n            name: "' + member + r'",.*?\n        \),', text, re.S)[0]
        globs = re.findall(r'"([^"]+)"', re.search(r'sources:\s*\[(.*?)\]', body, re.S)[1])
        for source_glob in globs:
            files.extend(root.glob(source_glob + "/*.swift" if source_glob.endswith("**") else source_glob))
    files = sorted(set(files))
    if len(files) < 140:
        raise ValueError(f"Expected the grouped library sources, found {len(files)}")
    manifest_hashes = {}
    for seed, bundle in VARIANTS.items():
        directory = root / "OrderProbeSwift" / bundle
        directory.mkdir(parents=True)
        shuffled = sorted(files, key=lambda path: sha256(f"{seed}/{path.relative_to(root)}".encode()).digest())
        manifest_hashes[bundle] = {}
        for rank, path in enumerate(shuffled):
            data = path.read_bytes()
            copy = directory / f"{rank:04d}_{path.name}"
            copy.write_bytes(data)
            if copy.read_bytes() != data:
                raise ValueError(f"Source copy changed: {path}")
            manifest_hashes[bundle][str(path.relative_to(root))] = {
                "prefix": rank, "sha256": sha256(data).hexdigest()
            }
    def once(old, new):
        nonlocal text
        if text.count(old) != 1:
            raise ValueError(f"Unexpected manifest marker: {old}")
        text = text.replace(old, new)
    once("    return targets + [group]", '''    let variants = ["GroupedOrderAlphaTests", "GroupedOrderBetaTests"].map { name in
        var variant = group
        variant.name = name
        variant.bundleId = "com.stuff.orderprobe.\\(name.lowercased())"
        variant.sources = .sourceFilesList(globs: ["OrderProbeSwift/\\(name)/**"])
        return variant
    }
    return targets + [group] + variants''')
    full = re.search(r'(name: "Stuff-iOS-FullTests",\s*testNames: )\[groupedLibraryTargetName\] \+ ordinaryTestNames\s*\.filter \{ !groupedLibraryTestNames.contains\(\$0\) \}', text)
    if not full:
        raise ValueError("Full scheme declaration missing")
    once(full[0], full[1] + "[" + ", ".join(json.dumps(b) for b in BUNDLES) + "]")
    once('let hostsAndApps = ["Where", "RegionViewer", "StuffTestHost", "BroadwayCatalog"]', 'let hostsAndApps = ["StuffTestHost"]')
    manifest.write_text(text)
    (evidence / "source-hashes-and-ranks.json").write_text(json.dumps(manifest_hashes, indent=2) + "\n")
    print(f"Prepared {len(files)} byte-identical test sources for each of {list(VARIANTS.values())}.")


def read_result(bundle, *command):
    return json.loads(subprocess.check_output(["xcrun", "xcresulttool", "get", *command, "--path", str(bundle), "--compact"]))


def summarize(work, evidence):
    bundle = work / "Stuff-iOS-FullTests.xcresult"
    result = read_result(bundle, "test-results", "tests")
    action = read_result(bundle, "log", "--type", "action")
    cases = {b: Counter() for b in BUNDLES}
    counts = {b: Counter() for b in BUNDLES}
    def visit(n, owner=None, case=None, argument=None):
        kind = n["nodeType"]
        if kind == "Unit test bundle":
            owner = n["name"]
            if owner not in cases:
                raise ValueError(f"Unexpected test bundle {owner}")
        if kind == "Test Case":
            case = n["nodeIdentifier"]
            counts[owner][n["result"]] += 1
            cases[owner][("case", case, n["result"])] += 1
        if kind == "Arguments":
            argument = n["name"]
            for name in BUNDLES:
                argument = argument.replace(name + ".", BASE + ".")
            if case == "LogContextExportRequirementsTests/unclassifiedContextRequiresEveryBuiltInGrant(_:)":
                # Xcode truncates the string description of a Set of equivalent grants.
                argument = "<unclassified grants>"
            if case == "LogExportMetadataTests/persistedNestedPoliciesMatchLiveProjection(policy:)":
                argument = re.sub(r'Set\(\[(.*?)\]\)', lambda m: "Set([" + ",".join(sorted(m[1].split(", "))) + "])", argument)
            cases[owner][("arg", case, argument, n["result"])] += 1
        if kind == "Repetition":
            cases[owner][("repetition", case, argument, n["name"], n["result"])] += 1
        for c in n.get("children", []):
            visit(c, owner, case, argument)
    for n in result["testNodes"]:
        visit(n)
    orders = {}
    for target in action["subsections"]:
        name = target["title"].removeprefix("Test target ")
        if name not in BUNDLES:
            continue
        nodes = [n for host in target["subsections"] for n in host.get("subsections", [])]
        names = [(n["startTime"], n["testDetails"]["suiteName"]) for n in nodes if n.get("testDetails", {}).get("suiteName") not in (None, "All tests", "Selected tests")]
        orders[name] = [suite for _, suite in sorted(names)]
    measured = {"counts": counts, "orders": orders, "changedPairFractions": {}, "caseDifferences": {}}
    errors = []
    if set(orders) != set(BUNDLES):
        errors.append(f"Missing test-host results: {set(BUNDLES) - set(orders)}")
    for name in BUNDLES:
        diff = (cases[BASE] - cases[name]) + (cases[name] - cases[BASE])
        measured["caseDifferences"][name] = [[list(k), v] for k, v in diff.items()]
        if counts[name] != {"Passed": 922} or diff:
            errors.append(f"{name}: {counts[name]}, {sum(diff.values())} differing outcomes")
    for left, right in combinations(orders, 2):
        a, b = orders[left], orders[right]
        if len(set(a)) != len(a) or len(set(b)) != len(b) or set(a) != set(b) or len(a) != 147:
            errors.append(f"{left}/{right}: unexpected or unequal suites: {len(a)}/{len(b)}")
            continue
        ranks = {s: i for i, s in enumerate(b)}
        pairs = list(combinations(a, 2))
        fraction = sum(ranks[x] > ranks[y] for x, y in pairs) / len(pairs)
        measured["changedPairFractions"][f"{left} vs {right}"] = round(fraction, 5)
        if fraction < 0.2:
            errors.append(f"{left}/{right}: only {fraction:.1%} of suite pairs changed order")
    measured["errors"] = errors
    (evidence / "results.json").write_text(json.dumps(measured, indent=2) + "\n")
    lines = ["# Serial iOS test ordering", ""]
    for name in BUNDLES:
        lines.append(f"- {name}: {dict(counts[name])}; first five suites: {', '.join(orders.get(name, [])[:5])}.")
    lines += [""] + [f"- {key}: {value:.1%} of suite pairs changed order." for key,value in measured["changedPairFractions"].items()]
    lines += [""] + (errors or ["All 922 case IDs, outcomes, equivalent parameters and repetitions matched across the three processes."])
    (evidence / "report.md").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))
    if errors:
        raise SystemExit(1)


if __name__ == "__main__":
    root = Path.cwd()
    evidence = root / "test-output-order-probe" / "evidence"
    evidence.mkdir(parents=True, exist_ok=True)
    if sys.argv[1] == "prepare":
        prepare(root, evidence)
    else:
        summarize(Path(os.environ["TEST_WORKDIR"]), evidence)
