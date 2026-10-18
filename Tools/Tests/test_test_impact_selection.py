import copy
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from test_impact_selection import filtered_assignment, select, validate_metadata
from Fixtures.test_impact_fixtures import metadata


class ImpactSelectionTests(unittest.TestCase):
    def setUp(self):
        self.head = metadata()
        self.base = metadata("base")

    def plan(self, paths, mode="snapshot"):
        return select(self.head, self.base, paths, mode)

    def test_leaf_selects_one_suite_without_splitting_target(self):
        plan = self.plan(["UI/Card.swift"])
        self.assertEqual(plan["snapshots"], ["UISnapshotTests/CardTests"])
        self.assertEqual(plan["units"], ["UITests"])
        self.assertEqual(plan["narrowedBundles"], ["UISnapshotTests"])

    def test_transitive_helper_reaches_root(self):
        self.assertEqual(self.plan(["UI/Helper.swift"])["snapshots"], ["UISnapshotTests/CardTests"])

    def test_removal_of_reference_uses_old_graph(self):
        self.head["index"][0]["dependencies"] = []
        self.assertEqual(self.plan(["UI/Helper.swift"])["snapshots"], ["UISnapshotTests/CardTests"])

    def test_target_mode_keeps_entire_bundle_and_unrelated_change_skips_it(self):
        self.assertEqual(len(self.plan(["UI/Card.swift"], "target")["snapshots"]), 2)
        self.assertEqual(self.plan(["Ledger/Value.swift"])["snapshots"], [])
        self.assertEqual(self.plan(["README.md"])["snapshots"], [])

    def test_unknown_inputs_cannot_be_overridden_by_known_leaf(self):
        for path in ["unmodeled/new-input", ".circleci/config.yml", "Package.resolved", "Project.swift"]:
            with self.subTest(path=path):
                self.assertEqual(len(self.plan([path, "UI/Card.swift"])["snapshots"]), 2)

    def test_broad_resource_and_dynamic_changes_keep_bundle(self):
        self.assertEqual(len(self.plan(["UI/Resources/copy.json"])["snapshots"]), 2)
        self.head["index"][0]["syntax"]["risks"] = ["dynamic-behavior"]
        self.assertEqual(len(self.plan(["UI/Card.swift"])["snapshots"]), 2)

    def test_missing_index_added_overload_and_unsupported_root_keep_bundle(self):
        for mutation in ["missing", "unindexed", "new-declaration", "unsupported-root"]:
            with self.subTest(mutation=mutation):
                self.head = metadata()
                if mutation == "missing":
                    self.head["index"].pop()
                elif mutation == "unindexed":
                    self.head["index"][1]["indexed"] = False
                elif mutation == "new-declaration":
                    self.head["index"][0]["definitions"].append("newOverload")
                else:
                    self.head["index"][-1]["syntax"]["captures"] = []
                self.assertEqual(len(self.plan(["UI/Card.swift"])["snapshots"]), 2)

    def test_unsupported_roots_always_run_even_when_unrelated(self):
        self.head["index"][-1]["syntax"]["captures"] = []
        self.assertEqual(len(self.plan(["UI/Card.swift"])["snapshots"]), 2)

    def test_missing_base_selects_everything(self):
        self.assertEqual(len(select(self.head, None, ["README.md"], "snapshot")["snapshots"]), 2)

    def test_declaration_shape_changes_and_missing_build_identity_keep_bundle(self):
        for mutation in ["shape", "missing-shape", "index-revision"]:
            with self.subTest(mutation=mutation):
                self.head = metadata()
                if mutation == "shape":
                    self.head["index"][0]["syntax"]["shape"] = ["struct Card: NewProtocol {}"]
                elif mutation == "missing-shape":
                    del self.head["index"][0]["syntax"]["shape"]
                else:
                    self.head["indexRevision"] = "stale-build"
                self.assertEqual(len(self.plan(["UI/Card.swift"])["snapshots"]), 2)

    def test_metadata_rejects_incompatible_identity(self):
        validate_metadata(self.head, "head", self.head["environment"])
        for mutation in ["revision", "dirty", "version", "inventory", "environment"]:
            value = copy.deepcopy(self.head)
            if mutation == "inventory":
                value["catalog"]["suites"]["bad"] = "bad.swift"
            else:
                value[mutation] = "wrong"
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                validate_metadata(value, "head", self.head["environment"])

    def test_worker_filter_validates_identity_and_assignment(self):
        plan = self.plan(["UI/Card.swift"])
        assignment = sorted(self.head["catalog"]["suites"])
        self.assertEqual(filtered_assignment(plan, assignment, "head", self.head["environment"]), [assignment[0]])
        self.assertEqual(filtered_assignment(plan, [assignment[1]], "head", self.head["environment"]), [])
        for invalid in [assignment + [assignment[0]], ["Bogus/Suite"]]:
            with self.assertRaises(ValueError):
                filtered_assignment(plan, invalid, "head", self.head["environment"])
        with self.assertRaises(ValueError):
            filtered_assignment(plan, assignment, "stale", self.head["environment"])
