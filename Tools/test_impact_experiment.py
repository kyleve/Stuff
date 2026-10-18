"""Accounting and outcome analysis for the bounded selection experiment."""

from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import statistics
import xml.etree.ElementTree as ET


CREDIT_DOLLARS = 0.0006
BUDGET_DOLLARS = 250
MAX_RUNS = 30
# Includes all workers and preparation margin at the configured job timeouts.
RUN_RESERVATION_DOLLARS = 75


def new_ledger(baseline_revision):
    return {"version": 1, "baselineRevision": baseline_revision, "budgetDollars": BUDGET_DOLLARS,
            "startedAt": datetime.now(timezone.utc).isoformat(), "runs": [], "shadowDollars": 0}


def finite_number(value, label):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or value < 0:
        raise ValueError("invalid " + label)
    return value


def reserve(ledger, key, revision, mode, category, repetition):
    if ledger.get("version") != 1 or ledger.get("budgetDollars") != BUDGET_DOLLARS:
        raise ValueError("unsupported experiment ledger")
    if any(run["key"] == key for run in ledger["runs"]):
        raise ValueError("run already reserved; reconcile its existing dispatch")
    if any(run["status"] == "reserved" for run in ledger["runs"]):
        raise ValueError("finish or reconcile the active run before dispatching another")
    if any(run["status"] == "success" and (run["revision"], run["mode"], run["repetition"]) == (revision, mode, repetition)
           for run in ledger["runs"]):
        raise ValueError("successful comparison sample already exists")
    if len(ledger["runs"]) >= MAX_RUNS:
        raise ValueError("30-run limit reached")
    spent = finite_number(ledger["shadowDollars"], "shadow cost") + sum(
        finite_number(run["dollars"], "run cost") for run in ledger["runs"]
    )
    if spent + RUN_RESERVATION_DOLLARS > BUDGET_DOLLARS:
        raise ValueError("insufficient budget for another complete run")
    ledger["runs"].append({"key": key, "revision": revision, "mode": mode, "category": category,
                           "repetition": repetition, "status": "reserved", "dollars": RUN_RESERVATION_DOLLARS,
                           "reservationDollars": RUN_RESERVATION_DOLLARS})


def finish(ledger, key, result):
    matches = [run for run in ledger["runs"] if run["key"] == key]
    if len(matches) != 1 or matches[0]["status"] != "reserved":
        raise ValueError("no active reservation for this run")
    run = matches[0]
    if result["revision"] != run["revision"] or result["mode"] != run["mode"]:
        raise ValueError("result revision or selection mode mismatch")
    if result["status"] not in {"success", "failed", "canceled"}:
        raise ValueError("workflow is not terminal")
    if any(key in result for key in ("key", "category", "repetition", "reservationDollars")):
        raise ValueError("result cannot replace reservation identity")
    if "creditsUsed" in result:
        credits = finite_number(result["creditsUsed"], "credits")
        estimated = False
    else:
        if not result.get("workers"):
            raise ValueError("cost requires actual credits or every worker's runtime")
        credits = 0
        for worker in result["workers"]:
            rates = {"m4pro.large": 400, "m4pro.medium": 200}
            if worker["resourceClass"] not in rates:
                raise ValueError("unknown worker credit rate")
            credits += finite_number(worker["seconds"], "worker runtime") / 60 * rates[worker["resourceClass"]]
        estimated = True
    for field in ("elapsedSeconds", "queueSeconds", "runtimeSeconds"):
        finite_number(result[field], field)
    if result["queueSeconds"] > result["elapsedSeconds"]:
        raise ValueError("queue time exceeds elapsed time")
    run.update(result)
    run.update({"credits": credits, "dollars": credits * CREDIT_DOLLARS, "estimated": estimated})


def comparison(ledger):
    rows = []
    for baseline, mode in (("full", "target"), ("full", "snapshot"), ("target", "snapshot")):
        full = {(run["revision"], run["repetition"]): run for run in ledger["runs"]
                if run["status"] == "success" and run["mode"] == baseline}
        pairs = [(full[(run["revision"], run["repetition"])], run) for run in ledger["runs"]
                 if run["mode"] == mode and run["status"] == "success"
                 and (run["revision"], run["repetition"]) in full]
        if not pairs:
            rows.append({"baselineMode": baseline, "mode": mode, "pairs": 0})
            continue
        row = {"baselineMode": baseline, "mode": mode, "pairs": len(pairs), "estimated": any(a["estimated"] or b["estimated"] for a, b in pairs)}
        for field in ("elapsedSeconds", "queueSeconds", "runtimeSeconds", "credits", "dollars"):
            differences = [a[field] - b[field] for a, b in pairs]
            denominator = sum(a[field] for a, _ in pairs)
            row[field] = {"baselineMean": statistics.mean(a[field] for a, _ in pairs),
                          "selectedMean": statistics.mean(b[field] for _, b in pairs),
                          "medianSaved": statistics.median(differences), "minSaved": min(differences),
                          "maxSaved": max(differences), "percentSaved": 100 * sum(differences) / denominator if denominator else None}
        rows.append(row)
    return {"comparisons": rows, "spentDollars": ledger["shadowDollars"] + sum(run["dollars"] for run in ledger["runs"] if run["status"] != "reserved"),
            "reservedDollars": sum(run["dollars"] for run in ledger["runs"] if run["status"] == "reserved"),
            "terminalFailures": [run["key"] for run in ledger["runs"] if run["status"] in {"failed", "canceled"}],
            "qualification": "Preliminary paired observations; neither green runs nor synthetic mutations establish a population regression-detection rate."}


def shadow_audit(plan, junit_paths, verdicts, evidence_paths):
    artifacts = {}
    workflows = set()
    for path in evidence_paths:
        evidence = json.loads(Path(path).read_text())
        if (evidence.get("revision") != plan["head"] or evidence.get("mode") not in {"full", "shadow"}
                or evidence.get("environment") != plan["environment"] or not evidence.get("workflowID")):
            raise ValueError("full-run evidence does not match the plan revision/environment")
        workflows.add(evidence["workflowID"])
        for artifact in evidence["junit"]:
            target = (Path(path).parent / artifact["path"]).resolve()
            if target in artifacts:
                raise ValueError("duplicate JUnit evidence")
            artifacts[target] = artifact["sha256"]
    if len(workflows) != 1 or set(artifacts) != {Path(path).resolve() for path in junit_paths}:
        raise ValueError("audit requires all JUnit artifacts from exactly one full workflow")
    for path in junit_paths:
        if hashlib.sha256(Path(path).read_bytes()).hexdigest() != artifacts[Path(path).resolve()]:
            raise ValueError("JUnit artifact checksum mismatch")
    selected = set(plan["snapshots"])
    inventory = set(plan["snapshotInventory"])
    seen = set()
    failed = set()
    for path in junit_paths:
        root = ET.parse(path).getroot()
        for case in root.iter("testcase"):
            suite = case.get("file", "")
            # The repository's exporter writes its canonical Bundle/Suite identifier in file.
            if suite not in inventory:
                raise ValueError("JUnit contains an unknown snapshot suite: " + suite)
            if case.find("skipped") is None:
                seen.add(suite)
            if case.find("failure") is not None or case.find("error") is not None:
                failed.add(suite)
    if seen != inventory:
        raise ValueError("full-run evidence omits snapshot suites: " + ", ".join(sorted(inventory - seen)))
    omitted = failed - selected
    allowed = {"regression", "flake", "unresolved"}
    if any(value not in allowed for value in verdicts.values()):
        raise ValueError("invalid failure verdict")
    return {"head": plan["head"], "mode": plan["mode"], "workflowID": next(iter(workflows)),
            "selected": len(selected), "total": len(inventory),
            "omittedFailures": [{"suite": suite, "verdict": verdicts.get(suite, "unresolved")} for suite in sorted(omitted)],
            "blocksRollout": any(verdicts.get(suite, "unresolved") != "flake" for suite in omitted),
            "allConfirmedRegressionSuitesOmitted": bool({suite for suite in failed if verdicts.get(suite) == "regression"})
            and {suite for suite in failed if verdicts.get(suite) == "regression"} <= omitted}
