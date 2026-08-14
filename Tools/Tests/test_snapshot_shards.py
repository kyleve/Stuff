#!/usr/bin/env python3
"""Tests for deterministic snapshot-suite shards."""

import importlib.util
import pathlib
import tempfile
import unittest


SCRIPT = pathlib.Path(__file__).parents[1] / "snapshot_shards.py"
SPEC = importlib.util.spec_from_file_location("shard_suites", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ShardTests(unittest.TestCase):
    def make_repo(self, directory):
        repo = pathlib.Path(directory)
        source = repo / "Module" / "SnapshotTests"
        source.mkdir(parents=True)
        (repo / "Project.swift").write_text(
            '''
            unitTests(
                name: "ModuleSnapshotTests",
                sources: ["Module/SnapshotTests/**"],
            ),
            '''
        )
        for suite in ("FirstSnapshotTests", "SecondSnapshotTests", "ThirdSnapshotTests"):
            (source / f"{suite}.swift").write_text(
                f"import Testing\nstruct {suite} {{ @Test func example() {{}} }}\n"
            )
        return repo

    def make_plan(self):
        return {
            "formatVersion": 1,
            "shards": [
                {
                    "index": 0,
                    "suites": [
                        "ModuleSnapshotTests/FirstSnapshotTests",
                        "ModuleSnapshotTests/ThirdSnapshotTests",
                    ],
                },
                {
                    "index": 1,
                    "suites": ["ModuleSnapshotTests/SecondSnapshotTests"],
                },
            ],
        }

    def test_validates_a_complete_source_partition(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = self.make_repo(directory)

            inventory, partition = MODULE.validate_plan(self.make_plan(), repo)

            self.assertEqual(len(inventory), 3)
            self.assertEqual(len(partition), 2)

    def test_rejects_a_suite_that_is_missing_from_the_plan(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = self.make_repo(directory)
            plan = self.make_plan()
            plan["shards"][0]["suites"].remove(
                "ModuleSnapshotTests/ThirdSnapshotTests"
            )

            with self.assertRaisesRegex(ValueError, "omits suites"):
                MODULE.validate_plan(plan, repo)

    def test_rejects_an_empty_shard(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = self.make_repo(directory)
            plan = self.make_plan()
            plan["shards"][1]["suites"] = []

            with self.assertRaisesRegex(ValueError, "shard 1 is empty"):
                MODULE.validate_plan(plan, repo)

    def test_rejects_overlapping_shards(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = self.make_repo(directory)
            plan = self.make_plan()
            plan["shards"][1]["suites"].append(
                "ModuleSnapshotTests/FirstSnapshotTests"
            )

            with self.assertRaisesRegex(ValueError, "overlap"):
                MODULE.validate_plan(plan, repo)

    def test_rejects_a_test_file_with_a_different_suite_name(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = self.make_repo(directory)
            path = repo / "Module" / "SnapshotTests" / "ThirdSnapshotTests.swift"
            path.write_text("import Testing\nstruct RenamedTests { @Test func x() {} }\n")

            with self.assertRaisesRegex(ValueError, "must declare one top-level suite"):
                MODULE.source_inventory(repo)

    def test_compares_the_plan_with_xcode_enumeration(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "suites.txt"
            plan = self.make_plan()
            suites = sorted(
                suite for shard in MODULE.plan_partition(plan) for suite in shard
            )
            path.write_text("".join(f"{suite}\n" for suite in suites))

            MODULE.validate_enumeration(plan, path)

            path.write_text("ModuleSnapshotTests/NewSnapshotTests\n")
            with self.assertRaisesRegex(ValueError, "does not match"):
                MODULE.validate_enumeration(plan, path)

    def test_rebalances_by_median_duration_with_a_stable_tie_break(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = self.make_repo(directory)
            documents = []
            for index, durations in enumerate(((9, 5, 4), (11, 5, 2), (10, 5, 3))):
                path = repo / f"results-{index}.xml"
                path.write_text(
                    "<testsuites><testsuite>"
                    + "".join(
                        f'<testcase file="ModuleSnapshotTests/{suite}" time="{elapsed}" />'
                        for suite, elapsed in zip(
                            (
                                "FirstSnapshotTests",
                                "SecondSnapshotTests",
                                "ThirdSnapshotTests",
                            ),
                            durations,
                        )
                    )
                    + "</testsuite></testsuites>"
                )
                documents.append(path)

            candidate = MODULE.rebalanced_plan(self.make_plan(), repo, documents)

            self.assertEqual(candidate["timings"]["ModuleSnapshotTests/FirstSnapshotTests"], 10)
            self.assertEqual(candidate["shards"][0]["estimatedSeconds"], 10)
            self.assertEqual(candidate["shards"][1]["estimatedSeconds"], 8)

    def test_rejects_incomplete_timing_documents(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = self.make_repo(directory)
            path = repo / "results.xml"
            path.write_text(
                '<testsuites><testcase file="ModuleSnapshotTests/FirstSnapshotTests" '
                'time="1" /></testsuites>'
            )

            with self.assertRaisesRegex(ValueError, "no durations"):
                MODULE.rebalanced_plan(self.make_plan(), repo, [path])


if __name__ == "__main__":
    unittest.main()
