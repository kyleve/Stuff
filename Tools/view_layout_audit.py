"""Discovery, generated probe coverage, and compiled-layout budget policy."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

from Tools.repository import repository_root
from Tools.view_layout_runner import execute, fingerprint

BEGIN = "// BEGIN GENERATED VIEW LAYOUT AUDIT"
END = "// END GENERATED VIEW LAYOUT AUDIT"
REGISTRY = "ViewLayoutAudit.generated.swift"
LIMIT = 16384
CONFIG_DIR = Path("Tools/ViewLayoutAudit")
VIEW_BASES = {"View", "UIViewRepresentable", "UIViewControllerRepresentable", "NSViewRepresentable", "NSViewControllerRepresentable", "Shape", "InsettableShape"}
EXCLUDED_MODULES = {"SnapshotKitTesting", "TestHostSupport", "StuffTestHost", "PeriscopeMacros"}


def run(argv, *, cwd, **kwargs):
    return subprocess.run(argv, cwd=cwd, check=True, text=True, **kwargs)


def sources(root):
    return sorted(p.relative_to(root).as_posix() for area in ("Shared", "Where", "Ledger")
                  for p in (root / area).rglob("*.swift")
                  if "Sources" in p.parts and "Prototypes" not in p.parts
                  and not set(p.parts).intersection(EXCLUDED_MODULES) and p.name != REGISTRY)


def module_for(path):
    parts = Path(path).parts
    return parts[parts.index("Sources") - 1]


def select_candidates(raw):
    # Resolve local protocol inheritance before choosing conformers. SwiftSyntax
    # has no semantic type checker; unsupported aliases need explicit coverage.
    bases = set(VIEW_BASES)
    changed = True
    while changed:
        changed = False
        for declarations in raw.values():
            for declaration in declarations:
                if set(declaration["bases"]) & bases and declaration["name"] not in bases:
                    bases.add(declaration["name"])
                    changed = True
    result = {}
    grouped = {}
    generic_names = {(module_for(path), declaration["name"]) for path, declarations in raw.items()
                     for declaration in declarations if declaration["generic"]}
    for path, declarations in sorted(raw.items()):
        for declaration in declarations:
            if not set(declaration["bases"]) & bases:
                continue
            key = (module_for(path), declaration["name"])
            grouped.setdefault(key, []).append((path, declaration))
    for key, matches in grouped.items():
        definitions = [(path, declaration) for path, declaration in matches if declaration["kind"] != "extension"]
        if len(definitions) > 1:
            raise ValueError(f"Ambiguous view declarations for {key}: {[path for path, _ in definitions]}")
        path, declaration = (definitions or matches)[0]
        declaration = dict(declaration, generic=key in generic_names)
        result.setdefault(path, []).append(declaration)
    return result


def discover(root, executable=None):
    if executable is None:
        run(["swift", "build", "--product", "ViewLayoutDiscovery"], cwd=root, stdout=sys.stderr)
        executable = root / ".build/debug/ViewLayoutDiscovery"
    files = sources(root)
    result = run([str(executable), *files], cwd=root, capture_output=True)
    return select_candidates(json.loads(result.stdout))


def load_json(path):
    with path.open() as handle:
        return json.load(handle)


def swift_string(value):
    # JSON escaping is valid for these ASCII IDs and source paths. This is Swift
    # source generation, never shell interpolation.
    if not value.isascii():
        return '"' + value.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n') + '"'
    return json.dumps(value)


def probe_name(path):
    return "_viewLayout_" + hashlib.sha256(path.encode()).hexdigest()[:16]


def without_hooks(text):
    if BEGIN not in text:
        return text
    if text.count(BEGIN) != 1 or text.count(END) != 1:
        raise ValueError("Malformed generated audit block")
    start = text.index(BEGIN)
    finish = text.index(END) + len(END)
    if text[finish:].strip():
        raise ValueError("Generated audit block must be at end of file")
    return text[:start].rstrip() + "\n"


def probe_cases(inventory, registrations):
    result = []
    used = set()
    for path, declarations in inventory.items():
        for declaration in declarations:
            name = declaration["name"]
            key = f"{module_for(path)}/{name}"
            registration = registrations.get(key)
            if registration is not None:
                used.add(key)
                if not registration.get("reason", "").strip():
                    raise ValueError(f"{key}: registration needs a reason")
            if declaration["generic"] and registration is None:
                raise ValueError(f"{path}:{declaration['line']}: {key} needs concrete cases or an exemption")
            if registration and "exemption" in registration:
                if not registration["exemption"].strip():
                    raise ValueError(f"{key}: empty exemption")
                cases = [None]
            else:
                cases = registration["types"] if registration else [name]
                if not isinstance(cases, list) or not cases or any(not isinstance(value, str) or not value.strip() for value in cases) or len(set(cases)) != len(cases):
                    raise ValueError(f"{key}: empty or duplicate cases")
            for concrete in cases:
                result.append({"id": f"{key}:{concrete or 'exempt'}", "path": path,
                               "line": declaration["line"], "condition": declaration["condition"],
                               "type": concrete, "registration": registration})
    stale = set(registrations) - used
    if stale:
        raise ValueError(f"Stale registrations: {sorted(stale)}")
    ids = [case["id"] for case in result]
    if len(ids) != len(set(ids)):
        raise ValueError("Duplicate probe IDs")
    return result


def generated_files(root, cases):
    by_file = {}
    for case in cases:
        by_file.setdefault(case["path"], []).append(case)
    outputs = {}
    modules = {}
    for path in sources(root):
        original = (root / path).read_text()
        clean = without_hooks(original)
        entries = by_file.get(path, [])
        if not entries:
            if clean != original:
                outputs[path] = clean
            continue
        module = module_for(path)
        source_root = Path(*Path(path).parts[:Path(path).parts.index("Sources") + 1])
        modules.setdefault((module, source_root), []).append(probe_name(path))
        lines = [BEGIN, "// Generated by ./view-layout-audit generate. Do not edit this block.", "// swiftformat:disable all", "#if VIEW_LAYOUT_AUDIT", "@MainActor", f"func {probe_name(path)}() -> [String] {{", "    var records: [String] = []"]
        for case in entries:
            condition = case["condition"]
            if condition:
                lines.append(f"    #if {condition}")
            if case["type"] is None:
                record = json.dumps({"id": case["id"], "status": "exempt"}, separators=(",", ":"))
                lines.append(f"    records.append({swift_string(record)})")
            else:
                lines.append(f"    records.append(_ViewLayoutAuditRegistry.measure({case['type']}.self, id: {swift_string(case['id'])}))")
            if condition:
                record = json.dumps({"id": case["id"], "status": "inactive"}, separators=(",", ":"))
                lines += ["    #else", f"    records.append({swift_string(record)})", "    #endif"]
        lines += ["    return records", "}", "#endif", "// swiftformat:enable all", END]
        outputs[path] = clean.rstrip() + "\n\n" + "\n".join(lines) + "\n"
    for (module, source_root), functions in modules.items():
        outputs[str(source_root / REGISTRY)] = registry_source(module, functions)
    return outputs


def registry_source(module, functions):
    lines = ["// Generated by ./view-layout-audit generate. Do not edit.", "// swiftformat:disable all", "#if VIEW_LAYOUT_AUDIT", "import Foundation", "import SwiftUI", "", "/// Audit-only metatype measurements; never constructs production views.", "@_spi(Testing)", "@MainActor", "public enum _ViewLayoutAuditRegistry {", "    public static func records() -> [String] {", "        var records: [String] = []" if functions else "        let records: [String] = []"]
    lines += [f"        records += {function}()" for function in sorted(functions)]
    lines += ["        return records", "    }", "", "    static func measure<V: View>(_: V.Type, id: String) -> String {", '        FileHandle.standardError.write(Data("VIEW_LAYOUT_AUDIT_PROBE \(id)\\n".utf8))', '        let sample = Sample(id: id, status: "measured", view: Layout(V.self), body: Layout(V.Body.self))', "        do {", "            return String(decoding: try JSONEncoder().encode(sample), as: UTF8.self)", "        } catch {", '            fatalError("Cannot encode layout measurement: \\(error)")', "        }", "    }", "", "    private struct Sample: Encodable {", "        let id: String", "        let status: String", "        let view: Layout", "        let body: Layout", "    }", "", "    private struct Layout: Encodable {", "        let size: Int", "        let stride: Int", "        let alignment: Int", "        init<T>(_: T.Type) {", "            size = MemoryLayout<T>.size", "            stride = MemoryLayout<T>.stride", "            alignment = MemoryLayout<T>.alignment", "        }", "    }", "}"]
    if module == "Flyover":
        lines += ["enum _LayoutAuditScreenID: Hashable { case example }"]
    lines += ["#endif", "// swiftformat:enable all", ""]
    return "\n".join(lines)


def write_transaction(root, outputs):
    if not outputs:
        return
    (root / ".build").mkdir(exist_ok=True)
    # Reuse the repository's rollback/backup implementation for multi-file edits.
    with tempfile.TemporaryDirectory(prefix="view-layout-", dir=root / ".build") as directory:
        operations = []
        for index, (path, text) in enumerate(outputs.items()):
            staged = Path(directory) / str(index)
            staged.write_text(text)
            operations.append({"target": str(root / path), "staged": str(staged)})
        ruby = 'require "json"; require "./Tools/file_transaction"; t = FileTransaction.new; JSON.parse(STDIN.read).each { |o| t.replace(target: o.fetch("target"), staged: o.fetch("staged")) }; t.commit'
        run(["mise", "exec", "--", "ruby", "-e", ruby], cwd=root, input=json.dumps(operations))


def validate_baseline(cases, baseline):
    if baseline.get("version") != 1 or not isinstance(baseline.get("budgets"), dict):
        raise ValueError("Unsupported baseline format")
    identifiers = {case["id"] for case in cases if case["type"] is not None}
    for key, budget in baseline["budgets"].items():
        platform, configuration, architecture, identifier = key.split("/", 3)
        identifier, part = identifier.rsplit("/", 1)
        if platform not in ("macOS", "iOSSimulator") or configuration not in ("Debug", "Beta", "Release") or architecture not in ("arm64", "x86_64") or part not in ("view", "body"):
            raise ValueError(f"Invalid baseline key: {key}")
        if identifier not in identifiers:
            raise ValueError(f"Stale baseline type: {key}")
        if type(budget.get("stride")) is not int or budget["stride"] < LIMIT or not budget.get("reason", "").strip():
            raise ValueError(f"Invalid baseline budget: {key}")


def validate_report(report, cases, baseline):
    identity = report["build"]
    for key in ("configuration", "platform", "architecture", "xcode", "commit"):
        if not isinstance(identity.get(key), str) or not identity[key]:
            raise ValueError(f"Missing build identity: {key}")
    if identity["platform"] not in ("macOS", "iOSSimulator") or identity["configuration"] not in ("Debug", "Beta", "Release") or identity["architecture"] not in ("arm64", "x86_64"):
        raise ValueError("Unsupported report platform/configuration/architecture")
    expected = {case["id"]: case for case in cases if identity["platform"] in case["platforms"]}
    measured = {}
    errors = []
    for sample in report["samples"]:
        key = sample["id"]
        if key in measured:
            errors.append(f"Duplicate measurement: {key}")
        measured[key] = sample
    if set(expected) != set(measured):
        errors.append(f"Missing measurements: {sorted(set(expected) - set(measured))}; unexpected: {sorted(set(measured) - set(expected))}")
    budgets = baseline.get("budgets", {})
    prefix = '/'.join(identity[key] for key in ("platform", "configuration", "architecture")) + "/"
    used = set()
    for key, sample in measured.items():
        if key not in expected:
            continue
        case = expected[key]
        location = f"{case['path']}:{case['line']}"
        status = sample.get("status")
        if status == "inactive":
            if not case["condition"]:
                errors.append(f"{location}: unexpected inactive probe {key}")
            continue
        if status == "exempt":
            if case["type"] is not None:
                errors.append(f"{location}: unregistered exemption {key}")
            continue
        if status != "measured" or case["type"] is None:
            errors.append(f"{location}: invalid status for {key}: {status}")
            continue
        for part in ("view", "body"):
            layout = sample[part]
            size, stride, alignment = (layout[field] for field in ("size", "stride", "alignment"))
            if any(type(value) is not int or value < 0 for value in (size, stride, alignment)) or alignment < 1 or alignment & (alignment - 1) or stride < size or stride % alignment:
                raise ValueError(f"Invalid layout for {key}.{part}")
            budget_key = prefix + key + "/" + part
            budget = budgets.get(budget_key)
            if budget:
                used.add(budget_key)
                if not budget.get("reason", "").strip() or type(budget.get("stride")) is not int or budget["stride"] < LIMIT:
                    raise ValueError(f"Invalid exception: {budget_key}")
                if stride < LIMIT:
                    errors.append(f"{location}: remove resolved baseline exception {budget_key}")
            ceiling = budget["stride"] if budget else LIMIT - 1
            if stride > ceiling:
                errors.append(f"{location}: error: {key}.{part} stride {stride} exceeds {ceiling} bytes (+{stride - ceiling})")
    for key in budgets:
        if key.startswith(prefix) and key not in used:
            errors.append(f"Stale baseline exception: {key}")
    return errors


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["check", "generate", "validate", "baseline", "fingerprint", "run", "self-test"])
    parser.add_argument("--discovery", type=Path, help="Use an already-built discovery executable")
    parser.add_argument("--report", type=Path)
    parser.add_argument("--reason", help="Required explanation for an explicit baseline update")
    parser.add_argument("--products", type=Path, help="Exact built-products directory; run never builds")
    parser.add_argument("--platform", choices=["macOS", "iOSSimulator"])
    parser.add_argument("--configuration", choices=["Debug", "Beta", "Release"])
    parser.add_argument("--output", type=Path, default=Path(".build/view-layout-report"))
    parser.add_argument("--shared", action="store_true")
    parser.add_argument("--os", help="Simulator runtime version")
    args = parser.parse_args(argv)
    root = repository_root(__file__)
    try:
        if args.command == "self-test":
            with tempfile.TemporaryDirectory(prefix="layout-probe-") as directory:
                generated = Path(directory) / "Registry.swift"
                generated.write_text(registry_source("Fixture", []))
                executable = Path(directory) / "probe"
                run(["xcrun", "swiftc", "-parse-as-library", "-DVIEW_LAYOUT_AUDIT", str(generated), str(root / CONFIG_DIR / "Fixtures/CompiledProbe.swift"), "-o", str(executable)], cwd=root)
                measured = [json.loads(line) for line in run([str(executable)], cwd=root, capture_output=True).stdout.splitlines()]
                values = {sample["id"]: sample for sample in measured}
                if set(values) != {"oversized", "split", "generic-wide", "generic-small"}:
                    raise ValueError("Compiled fixture did not produce all measurements")
                if values["oversized"]["body"]["stride"] < LIMIT or values["split"]["body"]["stride"] >= LIMIT:
                    raise ValueError("Compiled oversized/split regression failed")
                if values["generic-wide"]["view"]["stride"] <= values["generic-small"]["view"]["stride"]:
                    raise ValueError("Concrete generic specialization was not measured")
                library = Path(directory) / "NoAudit.dylib"
                run(["xcrun", "swiftc", "-emit-library", str(generated), "-o", str(library)], cwd=root)
                symbols = run(["nm", "-g", str(library)], cwd=root, capture_output=True).stdout
                if "ViewLayoutAuditRegistry" in symbols:
                    raise ValueError("Audit symbols leaked into an ordinary build")
                print("Compiled probe passed: private access, trapping initializer/body, oversized/split, generic specialization, ordinary-build exclusion")
            return 0
        if args.command == "fingerprint":
            print(fingerprint(root))
            return 0
        if args.command == "run":
            if not args.products or not args.platform or not args.configuration:
                raise ValueError("run requires --products, --platform, and --configuration")
            simulator_args = (["--shared"] if args.shared else []) + (["--os", args.os] if args.os else [])
            args.report = execute(root, args.products, args.platform, args.configuration, args.output, simulator_args)
        inventory = discover(root, args.discovery)
        registrations = load_json(root / CONFIG_DIR / "registrations.json")
        cases = probe_cases(inventory, registrations)
        platforms = load_json(root / CONFIG_DIR / "platforms.json")
        discovered_modules = {module_for(case["path"]) for case in cases}
        if set(platforms) != discovered_modules:
            raise ValueError(f"Platform registrations differ from discovered modules: {sorted(set(platforms) ^ discovered_modules)}")
        for case in cases:
            assigned = platforms[module_for(case["path"])]
            if not assigned or not isinstance(assigned, list) or not set(assigned) <= {"macOS", "iOSSimulator"}:
                raise ValueError(f"Invalid platform registration: {case['path']}")
            case["platforms"] = assigned
        validate_baseline(cases, load_json(root / CONFIG_DIR / "baseline.json"))
        outputs = generated_files(root, cases)
        existing_registries = {p.relative_to(root).as_posix() for area in ("Shared", "Where", "Ledger") for p in (root / area).rglob(REGISTRY)}
        stale_registries = existing_registries - set(outputs)
        if stale_registries:
            raise ValueError(f"Remove stale module registries and runner imports: {sorted(stale_registries)}")
        if args.command in ("check", "generate"):
            changed = {path: text for path, text in outputs.items() if not (root / path).exists() or (root / path).read_text() != text}
            if args.command == "check" and changed:
                raise ValueError("Outdated probes; run ./view-layout-audit generate:\n" + "\n".join(changed))
            if args.command == "generate":
                (root / ".build").mkdir(exist_ok=True)
                write_transaction(root, changed)
            print(f"Layout audit: {len(cases)} cases in {len(inventory)} source files; {len(changed)} changed files")
            return 0
        if args.report is None:
            raise ValueError("--report is required")
        report = load_json(args.report)
        if report["build"].get("inputHash") != fingerprint(root):
            raise ValueError("Report source fingerprint differs from this checkout; rebuild before updating budgets")
        commit = run(["git", "rev-parse", "HEAD"], cwd=root, capture_output=True).stdout.strip()
        if report["build"].get("commit") != commit:
            raise ValueError("Report commit differs from this checkout")
        if args.command == "run":
            by_id = {case["id"]: case for case in cases}
            locations = {case["id"]: {"path": case["path"], "line": case["line"]} for case in cases}
            for sample in report["samples"]:
                if sample["id"] in locations:
                    sample["source"] = locations[sample["id"]]
                    if by_id[sample["id"]]["registration"] is not None:
                        sample["coverage"] = by_id[sample["id"]]["registration"]
            args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
        baseline_path = root / CONFIG_DIR / "baseline.json"
        baseline = load_json(baseline_path)
        if args.command == "baseline":
            if not args.reason or not args.reason.strip():
                raise ValueError("--reason is required to update budgets")
            identity = report["build"]
            prefix = '/'.join(identity[key] for key in ("platform", "configuration", "architecture")) + "/"
            proposed = {key: value for key, value in baseline["budgets"].items() if not key.startswith(prefix)}
            for sample in report["samples"]:
                if sample["status"] == "measured":
                    for part in ("view", "body"):
                        if sample[part]["stride"] >= LIMIT:
                            proposed[prefix + sample["id"] + "/" + part] = {"stride": sample[part]["stride"], "reason": args.reason}
            baseline = {"version": 1, "budgets": proposed}
        errors = validate_report(report, cases, baseline)
        if args.command == "run":
            prefix = '/'.join(report["build"][key] for key in ("platform", "configuration", "architecture")) + "/"
            for sample in report["samples"]:
                if sample.get("status") == "measured":
                    for part in ("view", "body"):
                        ceiling = baseline["budgets"].get(prefix + sample["id"] + "/" + part, {}).get("stride", LIMIT - 1)
                        sample[part]["budget"] = ceiling
                        sample[part]["delta"] = sample[part]["stride"] - ceiling
            report["samples"].sort(key=lambda sample: (-max(sample.get("body", {}).get("stride", 0), sample.get("view", {}).get("stride", 0)), sample["id"]))
            report["errors"] = errors
            args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
            summary = [f"{sample.get('body', {}).get('stride', 0):7} body  {sample.get('view', {}).get('stride', 0):7} view  {sample['status']:8} {sample['id']}" for sample in sorted(report["samples"], key=lambda value: max(value.get("body", {}).get("stride", 0), value.get("view", {}).get("stride", 0)), reverse=True)]
            (args.output / "report.txt").write_text("\n".join(summary + errors) + "\n")
        if errors:
            raise ValueError("\n".join(errors))
        if args.command == "baseline":
            write_transaction(root, {str(CONFIG_DIR / "baseline.json"): json.dumps(baseline, indent=2, sort_keys=True) + "\n"})
        for sample in sorted(report["samples"], key=lambda value: max(value.get("view", {}).get("stride", 0), value.get("body", {}).get("stride", 0)), reverse=True):
            if sample["status"] == "measured":
                print(f"{sample['body']['stride']:7} body  {sample['view']['stride']:7} view  {sample['id']}")
        return 0
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
