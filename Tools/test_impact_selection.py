"""Conservative file-to-snapshot selection. This output is experimental, not a CI gate."""

from test_impact_graph import VERSION, affected, broad_input, closure, digest, global_input


def validate_metadata(metadata, revision, environment=None):
    if metadata.get("version") != VERSION or metadata.get("revision") != revision:
        raise ValueError("metadata revision or format mismatch")
    if metadata.get("dirty"):
        raise ValueError("metadata came from an uncommitted tree")
    if environment is not None and metadata.get("environment") != environment:
        raise ValueError("metadata toolchain or configuration mismatch")
    catalog = metadata["catalog"]
    if catalog["inventory"] != digest({"bundles": catalog["bundles"], "suites": catalog["suites"]}):
        raise ValueError("metadata inventory mismatch")


def select(head, base, paths, mode, fallback=None):
    catalog = head["catalog"]
    all_bundles = set(catalog["bundles"])
    reasons = []
    if mode == "full":
        selected = all_bundles
    elif fallback or base is None:
        selected = all_bundles
        reasons.append(fallback or "base metadata unavailable")
    else:
        selected, reasons = affected([base["catalog"], catalog], paths)
        selected &= all_bundles
    suites = {suite for suite in catalog["suites"] if suite.split("/")[0] in selected}
    narrowed = []
    force_full = any(reason.startswith(("global input:", "unknown input:")) for reason in reasons)
    if mode == "snapshot" and base is not None and not fallback and not force_full:
        current = {file["path"]: file for file in head.get("index", [])}
        previous = {file["path"]: file for file in base.get("index", [])}
        graph = {}
        for files in (previous, current):
            for path, file in files.items():
                graph.setdefault(path, set()).update(file["dependencies"])
        for bundle in sorted(selected):
            candidates = {suite for suite in suites if suite.split("/")[0] == bundle}
            if not candidates:
                continue
            inputs = set(catalog["bundles"][bundle]["inputs"])
            inputs.update(base["catalog"]["bundles"].get(bundle, {}).get("inputs", []))
            changed = set(paths) & inputs
            required = set(catalog["bundles"][bundle]["sources"])
            required.update(base["catalog"]["bundles"].get(bundle, {}).get("sources", []))
            problem = None
            if head.get("indexRevision") != head["revision"] or base.get("indexRevision") != base["revision"]:
                problem = "compiler index build identity unavailable"
            elif any(global_input(path) for path in paths):
                problem = "global input"
            elif not changed:
                problem = "no modeled changed input"
            elif any(not path.endswith(".swift") or broad_input(path) for path in changed):
                problem = "resource or shared infrastructure"
            elif any(path not in current or path not in previous for path in required | changed):
                problem = "missing base/head source index"
            elif any(not current[path]["indexed"] or not previous[path]["indexed"] for path in required):
                problem = "incomplete compiler index"
            elif any(current[path]["definitions"] != previous[path]["definitions"] for path in changed):
                problem = "declaration inventory changed"
            elif any("shape" not in current[path]["syntax"] or "shape" not in previous[path]["syntax"]
                     or current[path]["syntax"]["shape"] != previous[path]["syntax"]["shape"] for path in changed):
                problem = "declaration shape changed or unavailable"
            elif any(current[path]["syntax"]["risks"] or previous[path]["syntax"]["risks"] for path in changed):
                problem = "unsupported source behavior"
            if problem:
                reasons.append(f"{bundle}: {problem}; retained whole bundle")
                continue
            always = {suite for suite in candidates if not current[catalog["suites"][suite]]["syntax"]["captures"]}
            reached = {suite for suite in candidates - always if closure(graph, [catalog["suites"][suite]]) & changed}
            # A real source edit with no reachable test is not evidence that no test is affected.
            if not reached:
                reasons.append(f"{bundle}: no reachable snapshot; retained whole bundle")
                continue
            # An unrecognized capture style remains selected for every change to its bundle.
            # It does not supply evidence to exclude itself or another suite.
            keep = reached | always
            suites -= candidates - keep
            narrowed.append(bundle)
            reasons.append(f"{bundle}: {len(keep)}/{len(candidates)} suites reach changed files")
            if always:
                reasons.append(f"{bundle}: always retained {len(always)} unsupported capture roots")
    units = sorted(name for name in selected if not name.endswith("SnapshotTests")
                   and catalog["bundles"][name]["platform"] == "iOS")
    return {"version": VERSION, "experimental": True, "mode": mode,
            "head": head["revision"], "base": base["revision"] if base else None,
            "environment": head["environment"], "inventory": catalog["inventory"],
            "changed": sorted(paths), "units": units, "snapshots": sorted(suites),
            "selectedBundles": sorted(selected), "narrowedBundles": narrowed,
            "reasons": reasons, "snapshotInventory": sorted(catalog["suites"])}


def filtered_assignment(plan, assignment, head_revision, environment):
    if plan.get("version") != VERSION or plan.get("experimental") is not True:
        raise ValueError("invalid experiment plan")
    if plan.get("head") != head_revision or plan.get("environment") != environment:
        raise ValueError("plan does not match this build")
    inventory = set(plan["snapshotInventory"])
    if len(assignment) != len(set(assignment)) or not set(assignment) <= inventory:
        raise ValueError("worker assignment does not match the plan inventory")
    selected = plan["snapshots"]
    if len(selected) != len(set(selected)) or not set(selected) <= inventory:
        raise ValueError("plan contains duplicate or unknown suites")
    return sorted(set(assignment) & set(selected))
