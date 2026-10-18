from pathlib import Path
import hashlib
import json
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from test_impact_experiment import comparison, finish, new_ledger, reserve, shadow_audit


class ImpactExperimentTests(unittest.TestCase):
    def result(self, mode, credits=10000, status="success"):
        return {"revision": "sha", "mode": mode, "status": status, "creditsUsed": credits,
                "elapsedSeconds": 800, "queueSeconds": 100, "runtimeSeconds": 700}

    def test_budget_reserves_active_runs_and_rejects_duplicate_dispatch(self):
        ledger = new_ledger("baseline")
        reserve(ledger, "one", "sha", "full", "leaf", 1)
        with self.assertRaisesRegex(ValueError, "already reserved"):
            reserve(ledger, "one", "sha", "full", "leaf", 1)
        with self.assertRaisesRegex(ValueError, "active run"):
            reserve(ledger, "two", "sha", "target", "leaf", 1)
        finish(ledger, "one", self.result("full"))
        ledger["shadowDollars"] = 200
        with self.assertRaisesRegex(ValueError, "budget"):
            reserve(ledger, "two", "sha", "target", "leaf", 1)

    def test_counts_all_workers_and_excludes_failed_runs_from_savings(self):
        ledger = new_ledger("baseline")
        reserve(ledger, "full", "sha", "full", "leaf", 1)
        finish(ledger, "full", self.result("full"))
        reserve(ledger, "snapshot", "sha", "snapshot", "leaf", 1)
        result = self.result("snapshot")
        del result["creditsUsed"]
        result["workers"] = [{"resourceClass": "m4pro.large", "seconds": 60},
                             {"resourceClass": "m4pro.medium", "seconds": 60},
                             {"resourceClass": "m4pro.medium", "seconds": 60}]
        finish(ledger, "snapshot", result)
        self.assertEqual(ledger["runs"][-1]["credits"], 800)
        self.assertTrue(comparison(ledger)["comparisons"][1]["estimated"])
        reserve(ledger, "target", "sha", "target", "leaf", 1)
        finish(ledger, "target", self.result("target", status="failed"))
        self.assertEqual(comparison(ledger)["comparisons"][0]["pairs"], 0)
        self.assertEqual(comparison(ledger)["terminalFailures"], ["target"])

    def test_missing_or_untriaged_shadow_failures_block_rollout(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "results.xml"
            path.write_text('<testsuite><testcase file="B/A"/><testcase file="B/B"><failure/></testcase></testsuite>')
            plan = {"head": "sha", "mode": "snapshot", "environment": {},
                    "snapshots": ["B/A"], "snapshotInventory": ["B/A", "B/B"]}
            evidence = Path(directory) / "evidence.json"
            identity = {"revision": "sha", "mode": "shadow", "environment": {}, "workflowID": "workflow",
                        "junit": [{"path": path.name, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}]}
            evidence.write_text(json.dumps(identity))
            self.assertTrue(shadow_audit(plan, [path], {}, [evidence])["blocksRollout"])
            self.assertFalse(shadow_audit(plan, [path], {"B/B": "flake"}, [evidence])["blocksRollout"])
            identity["revision"] = "wrong"
            evidence.write_text(json.dumps(identity))
            with self.assertRaisesRegex(ValueError, "revision/environment"):
                shadow_audit(plan, [path], {}, [evidence])
            identity["revision"] = "sha"
            evidence.write_text(json.dumps(identity))
            plan["snapshotInventory"].append("B/C")
            with self.assertRaisesRegex(ValueError, "omits"):
                shadow_audit(plan, [path], {}, [evidence])
            path.write_text('<testsuite><testcase file="B/A"/></testsuite>')
            with self.assertRaisesRegex(ValueError, "checksum"):
                shadow_audit(plan, [path], {}, [evidence])

    def test_invalid_costs_cannot_release_budget(self):
        ledger = new_ledger("baseline")
        reserve(ledger, "full", "sha", "full", "leaf", 1)
        for credits in [-1, float("nan"), float("inf")]:
            with self.assertRaises(ValueError):
                finish(ledger, "full", self.result("full", credits))
        self.assertEqual(ledger["runs"][0]["status"], "reserved")

    def test_incremental_snapshot_comparison_uses_target_cost(self):
        ledger = new_ledger("baseline")
        for mode, credits in [("full", 10000), ("target", 8000), ("snapshot", 6000)]:
            reserve(ledger, mode, "sha", mode, "leaf", 1)
            finish(ledger, mode, self.result(mode, credits))
        row = comparison(ledger)["comparisons"][2]
        self.assertEqual(row["baselineMode"], "target")
        self.assertEqual(row["credits"]["medianSaved"], 2000)
        self.assertEqual(row["credits"]["percentSaved"], 25)
        with self.assertRaisesRegex(ValueError, "already exists"):
            reserve(ledger, "duplicate", "sha", "target", "leaf", 1)
