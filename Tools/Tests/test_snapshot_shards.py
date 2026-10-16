#!/usr/bin/env python3
"""Tests for deterministic snapshot-suite shards."""

import contextlib
import importlib.util
import io
import json
import pathlib
import random
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
import xml.etree.ElementTree as ET


SCRIPT = pathlib.Path(__file__).parents[1] / "snapshot_shards.py"
sys.path.insert(0, str(SCRIPT.parent))
SPEC = importlib.util.spec_from_file_location("shard_suites", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ShardTests(unittest.TestCase):
    def make_repo(self, directory):
        repo = pathlib.Path(directory)
        source = repo / "Module" / "SnapshotTests"
        source.mkdir(parents=True)
        (repo / "Project.swift").write_text(
            """
            unitTests(
                name: "ModuleSnapshotTests",
                sources: ["Module/SnapshotTests/**"],
            ),
            """
        )
        for suite in (
            "FirstSnapshotTests",
            "SecondSnapshotTests",
            "ThirdSnapshotTests",
        ):
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

    def test_multiline_sources_keep_shared_support_out_of_suite_discovery(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = self.make_repo(directory)
            other = repo / "Other" / "SnapshotTests"
            other.mkdir(parents=True)
            (other / "OtherTests.swift").write_text(
                "import Testing\nstruct OtherTests { @Test func example() {} }\n"
            )
            (repo / "Project.swift").write_text('''
            unitTests(
                name: "ModuleSnapshotTests",
                sources: [
                    "Module/Tests/Support/TestStore.swift",
                    "Module/SnapshotTests/**",
                ],
            ),
            unitTests(
                name: "OtherSnapshotTests",
                sources: ["Other/SnapshotTests/**"],
            ),
            ''')
            plan = self.make_plan()
            plan["shards"][0]["suites"].append("OtherSnapshotTests/OtherTests")
            path = repo / "plan.json"
            path.write_text(json.dumps(plan))

            self.assertEqual(MODULE.source_inventory(repo), {
                "ModuleSnapshotTests/FirstSnapshotTests",
                "ModuleSnapshotTests/SecondSnapshotTests",
                "ModuleSnapshotTests/ThirdSnapshotTests",
                "OtherSnapshotTests/OtherTests",
            })
            result = subprocess.run(
                [str(SCRIPT.parents[1] / "snapshot-shards"), "--plan", str(path),
                 "check", "--repo", str(repo)],
                cwd=repo, capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("4 suites", result.stdout)

    def test_source_array_without_a_snapshot_glob_cannot_borrow_the_next_target(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = self.make_repo(directory)
            project = repo / "Project.swift"
            project.write_text('''
            unitTests(
                name: "BrokenSnapshotTests",
                sources: ["Module/Tests/Support/TestStore.swift"],
            ),
            ''' + project.read_text())

            with self.assertRaisesRegex(ValueError, "BrokenSnapshotTests has no literal"):
                MODULE.source_inventory(repo)

    def test_nonliteral_sources_fail_without_borrowing_the_next_target(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = self.make_repo(directory)
            project = repo / "Project.swift"
            project.write_text('''
            unitTests(
                name: "BrokenSnapshotTests",
                sources: sharedSources,
            ),
            ''' + project.read_text())

            with self.assertRaisesRegex(ValueError, "literal source arrays.*BrokenSnapshotTests"):
                MODULE.source_inventory(repo)

    def test_rejects_a_suite_that_is_missing_from_the_plan(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = self.make_repo(directory)
            plan = self.make_plan()
            plan["shards"][0]["suites"].remove("ModuleSnapshotTests/ThirdSnapshotTests")

            with self.assertRaisesRegex(ValueError, "omits suites"):
                MODULE.validate_plan(plan, repo)

    def test_assigns_a_new_suite_to_the_intake_shard(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = self.make_repo(directory)
            source = repo / "Module" / "SnapshotTests"
            (source / "FourthSnapshotTests.swift").write_text(
                "import Testing\n"
                "struct FourthSnapshotTests { @Test func example() {} }\n"
            )

            inventory, partition = MODULE.execution_partition(self.make_plan(), repo)

            self.assertEqual(len(inventory), 4)
            self.assertEqual(
                partition[-1],
                ["ModuleSnapshotTests/FourthSnapshotTests"],
            )

    def test_leaves_the_intake_shard_empty_for_a_complete_plan(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = self.make_repo(directory)

            _, partition = MODULE.execution_partition(self.make_plan(), repo)

            self.assertEqual(partition[-1], [])

    def test_selects_an_empty_intake_shard(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = self.make_repo(directory)
            _, partition = MODULE.execution_partition(self.make_plan(), repo)

            selected = MODULE.selected_shard(partition, shard_number=3, worker_count=3)

            self.assertEqual(selected, [])

    def test_empty_intake_cli_writes_zero_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = self.make_repo(directory)
            plan = repo / "plan.json"
            plan.write_text(json.dumps(self.make_plan()))

            result = subprocess.run(
                [
                    sys.executable,
                    SCRIPT,
                    "--plan",
                    plan,
                    "list",
                    "3",
                    "--repo",
                    repo,
                    "--total",
                    "3",
                ],
                check=True,
                capture_output=True,
            )

            self.assertEqual(result.stdout, b"")

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
            plan["shards"][1]["suites"].append("ModuleSnapshotTests/FirstSnapshotTests")

            with self.assertRaisesRegex(ValueError, "overlap"):
                MODULE.validate_plan(plan, repo)

    def test_rejects_a_test_file_with_a_different_suite_name(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = self.make_repo(directory)
            path = repo / "Module" / "SnapshotTests" / "ThirdSnapshotTests.swift"
            path.write_text(
                "import Testing\nstruct RenamedTests { @Test func x() {} }\n"
            )

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

            MODULE.validate_enumeration(suites, path)

            path.write_text("ModuleSnapshotTests/NewSnapshotTests\n")
            with self.assertRaisesRegex(ValueError, "does not match"):
                MODULE.validate_enumeration(suites, path)

    def test_rejects_a_worker_count_that_differs_from_the_plan(self):
        partition = MODULE.plan_partition(self.make_plan())

        with self.assertRaisesRegex(ValueError, "started 3 workers"):
            MODULE.selected_shard(partition, 1, worker_count=3)

    def test_validates_that_each_assigned_suite_executed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            assignment = root / "shard.txt"
            assignment.write_text(
                "ModuleSnapshotTests/FirstSnapshotTests\n"
                "ModuleSnapshotTests/SecondSnapshotTests\n"
            )
            junit = root / "results.xml"
            self.write_junit(
                junit,
                [
                    "ModuleSnapshotTests/FirstSnapshotTests",
                    "ModuleSnapshotTests/FirstSnapshotTests",
                    "ModuleSnapshotTests/SecondSnapshotTests",
                ],
            )

            self.assertEqual(MODULE.validate_execution(assignment, junit), 2)

    def test_rejects_an_assigned_suite_that_did_not_execute(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            assignment = root / "shard.txt"
            assignment.write_text(
                "ModuleSnapshotTests/FirstSnapshotTests\n"
                "ModuleSnapshotTests/SecondSnapshotTests\n"
            )
            junit = root / "results.xml"
            self.write_junit(junit, ["ModuleSnapshotTests/FirstSnapshotTests"])

            with self.assertRaisesRegex(ValueError, "did not execute"):
                MODULE.validate_execution(assignment, junit)

    def test_rejects_an_executed_suite_that_was_not_assigned(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            assignment = root / "shard.txt"
            assignment.write_text("ModuleSnapshotTests/FirstSnapshotTests\n")
            junit = root / "results.xml"
            self.write_junit(
                junit,
                [
                    "ModuleSnapshotTests/FirstSnapshotTests",
                    "ModuleSnapshotTests/SecondSnapshotTests",
                ],
            )

            with self.assertRaisesRegex(ValueError, "unassigned suites"):
                MODULE.validate_execution(assignment, junit)

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

            candidate = MODULE.rebalance_report(self.make_plan(), repo, documents)

            self.assertEqual(
                candidate["timings"]["ModuleSnapshotTests/FirstSnapshotTests"], 10
            )
            self.assertEqual(candidate["afterSeconds"][0], 10)
            self.assertEqual(candidate["afterSeconds"][1], 8)

            candidate = MODULE.rebalance_report(
                self.make_plan(), repo, documents, shard_count=3
            )
            self.assertEqual(
                candidate["afterSeconds"][:-1],
                [10, 5, 3],
            )

    def test_rebalance_folds_an_intake_suite_into_the_plan(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = self.make_repo(directory)
            source = repo / "Module" / "SnapshotTests"
            (source / "FourthSnapshotTests.swift").write_text(
                "import Testing\n"
                "struct FourthSnapshotTests { @Test func example() {} }\n"
            )
            path = repo / "results.xml"
            path.write_text(
                "<testsuites>"
                '<testcase file="ModuleSnapshotTests/FirstSnapshotTests" time="9" />'
                '<testcase file="ModuleSnapshotTests/SecondSnapshotTests" time="5" />'
                '<testcase file="ModuleSnapshotTests/ThirdSnapshotTests" time="4" />'
                '<testcase file="ModuleSnapshotTests/FourthSnapshotTests" time="2" />'
                "</testsuites>"
            )

            candidate = MODULE.rebalance_report(self.make_plan(), repo, [path])
            assigned = {
                suite
                for shard in candidate["plan"]["shards"]
                for suite in shard["suites"]
            }

            self.assertIn("ModuleSnapshotTests/FourthSnapshotTests", assigned)

    def test_rejects_incomplete_timing_documents(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = self.make_repo(directory)
            path = repo / "results.xml"
            path.write_text(
                '<testsuites><testcase file="ModuleSnapshotTests/FirstSnapshotTests" '
                'time="1" /></testsuites>'
            )

            with self.assertRaisesRegex(ValueError, "no durations"):
                MODULE.rebalance_report(self.make_plan(), repo, [path])

    def test_stops_after_one_move_reaches_threshold(self):
        partition = [["A", "B", "C"], ["D"], ["E"], ["New"]]
        weights = {"A": 50, "B": 31, "C": 19, "D": 80, "E": 65, "New": 5}
        result = MODULE.stable_partition(partition, weights)
        self.assertEqual(result, [["A", "B"], ["D"], ["E", "New", "C"]])
        self.assertEqual(partition, [["A", "B", "C"], ["D"], ["E"], ["New"]])

    def test_intake_placement_alone_can_reach_target(self):
        partition = [["A"], ["B"], ["New1", "New2"]]
        weights = {"A": 10, "B": 10, "New1": 20, "New2": 20}
        self.assertEqual(
            MODULE.stable_partition(partition, weights), [["A", "New1"], ["B", "New2"]]
        )

    def test_discards_subthreshold_moves_but_keeps_intake(self):
        partition = [["A", "Small"], ["B"], ["New"]]
        weights = {"A": 97, "Small": 3, "B": 94, "New": 1}
        self.assertEqual(
            MODULE.stable_partition(partition, weights), [["A", "Small"], ["B", "New"]]
        )

    def test_accepts_exactly_five_percent(self):
        partition = [["A", "Small"], ["B"], []]
        weights = {"A": 95, "Small": 5, "B": 90}
        self.assertEqual(
            MODULE.stable_partition(partition, weights), [["A"], ["B", "Small"]]
        )

    def test_zero_durations_and_one_planned_shard(self):
        self.assertEqual(
            MODULE.stable_partition([["A"], ["New"]], {"A": 0, "New": 0}),
            [["A", "New"]],
        )

    def test_never_empties_a_planned_shard(self):
        partition = [["A"], ["B"], []]
        self.assertEqual(
            MODULE.stable_partition(partition, {"A": 100, "B": 1}), partition[:-1]
        )

    def balance_cli(self, repo, plan, junit, *extra):
        return subprocess.run(
            [
                str(SCRIPT.parents[1] / "snapshot-shards"),
                "--plan",
                str(plan),
                "balance",
                "--repo",
                str(repo),
                "--junit",
                str(junit),
                *extra,
            ],
            cwd=repo,
            capture_output=True,
            text=True,
        )

    def timing_fixture(self, repo, durations):
        path = repo / "timings.xml"
        root = ET.Element("testsuites")
        for suite, elapsed in zip(
            ("FirstSnapshotTests", "SecondSnapshotTests", "ThirdSnapshotTests"),
            durations,
        ):
            ET.SubElement(
                root,
                "testcase",
                file=f"ModuleSnapshotTests/{suite}",
                name=suite,
                time=str(elapsed),
            )
        ET.ElementTree(root).write(path, encoding="utf-8")
        return path

    def test_cli_dry_run_write_and_second_run_are_stable(self):
        with tempfile.TemporaryDirectory(prefix="shards ü ") as directory:
            repo = self.make_repo(directory)
            plan = repo / "plan.json"
            legacy = self.make_plan()
            legacy["timings"] = {"obsolete": 99}
            plan.write_text(json.dumps(legacy))
            original = plan.read_bytes()
            junit = self.timing_fixture(repo, [10, 5, 3])
            dry = self.balance_cli(repo, plan, junit)
            self.assertEqual(dry.returncode, 0, dry.stderr)
            report = json.loads(dry.stdout)
            self.assertTrue(report["changed"])
            self.assertEqual(len(report["movedSuites"]), 1)
            self.assertIn("Dry run", dry.stderr)
            self.assertEqual(plan.read_bytes(), original)
            written = self.balance_cli(repo, plan, junit, "--write")
            self.assertEqual(written.returncode, 0, written.stderr)
            self.assertEqual(json.loads(written.stdout), report)
            self.assertEqual(json.loads(plan.read_text()), report["plan"])
            self.assertEqual(set(report["plan"]), {"formatVersion", "shards"})
            self.assertTrue(
                all(
                    set(shard) == {"index", "suites"}
                    for shard in report["plan"]["shards"]
                )
            )
            self.assertIn("Updated", written.stderr)
            result = plan.read_bytes()
            again = self.balance_cli(repo, plan, junit, "--write")
            self.assertEqual(again.returncode, 0, again.stderr)
            self.assertFalse(json.loads(again.stdout)["changed"])
            self.assertIn("plan unchanged", again.stderr)
            self.assertEqual(plan.read_bytes(), result)

    def test_cli_does_not_refresh_legacy_metadata_without_rebalance(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = self.make_repo(directory)
            plan = repo / "plan.json"
            legacy = self.make_plan()
            legacy["sampleDocuments"] = 999
            plan.write_text(json.dumps(legacy))
            original = plan.read_bytes()
            junit = self.timing_fixture(repo, [5, 10, 5])
            result = self.balance_cli(repo, plan, junit, "--write")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(json.loads(result.stdout)["changed"])
            self.assertEqual(plan.read_bytes(), original)

    def test_cli_rejects_invalid_measurements_before_writing(self):
        for duration in ("nan", "inf", "-1", "invalid"):
            with (
                self.subTest(duration=duration),
                tempfile.TemporaryDirectory() as directory,
            ):
                repo = self.make_repo(directory)
                plan = repo / "plan.json"
                plan.write_text(json.dumps(self.make_plan()))
                original = plan.read_bytes()
                junit = self.timing_fixture(repo, [10, duration, 3])
                result = self.balance_cli(repo, plan, junit, "--write")
                self.assertEqual(result.returncode, 1)
                self.assertEqual(result.stdout, "")
                self.assertIn("duration is invalid", result.stderr)
                self.assertEqual(plan.read_bytes(), original)

    def test_rejects_failed_skipped_missing_and_duplicate_timing_inputs(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = self.make_repo(directory)
            for tag in ("failure", "error", "skipped"):
                path = self.timing_fixture(repo, [10, 5, 3])
                tree = ET.parse(path)
                ET.SubElement(tree.getroot().find("testcase"), tag)
                tree.write(path)
                with self.assertRaisesRegex(ValueError, tag):
                    MODULE.rebalance_report(self.make_plan(), repo, [path])
            path = self.timing_fixture(repo, [10, 5, 3])
            tree = ET.parse(path)
            del tree.getroot().find("testcase").attrib["time"]
            tree.write(path)
            with self.assertRaisesRegex(ValueError, "duration is invalid"):
                MODULE.rebalance_report(self.make_plan(), repo, [path])
            path = self.timing_fixture(repo, [10, 5, 3])
            with self.assertRaisesRegex(ValueError, "duplicate JUnit"):
                MODULE.rebalance_report(self.make_plan(), repo, [path, path])

    def test_cli_explicit_count_change_and_invalid_zero_count(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = self.make_repo(directory)
            plan = repo / "plan.json"
            plan.write_text(json.dumps(self.make_plan()))
            original = plan.read_bytes()
            junit = self.timing_fixture(repo, [10, 5, 3])
            invalid = self.balance_cli(repo, plan, junit, "--shards", "0", "--write")
            self.assertEqual(invalid.returncode, 1)
            self.assertIn("shard count must be positive", invalid.stderr)
            self.assertEqual(plan.read_bytes(), original)
            valid = self.balance_cli(repo, plan, junit, "--shards", "3", "--write")
            self.assertEqual(valid.returncode, 0, valid.stderr)
            report = json.loads(valid.stdout)
            self.assertEqual(report["reason"], "shard count changed")
            self.assertEqual(report["afterSeconds"], [10, 5, 3, 0])
            self.assertEqual(len(json.loads(plan.read_text())["shards"]), 3)

    def test_zero_duration_count_change_keeps_every_shard_nonempty(self):
        partition, totals = MODULE.balanced_partition({"A": 0, "B": 0, "C": 0}, 3)
        self.assertEqual(partition, [["A"], ["B"], ["C"]])
        self.assertEqual(totals, [0, 0, 0])

    def test_seeded_balances_preserve_coverage_and_gate_existing_moves(self):
        randomizer = random.Random(354)
        for _ in range(100):
            suites = [f"Suite{index}" for index in range(12)]
            weights = {suite: randomizer.randint(0, 100) for suite in suites}
            partition = [suites[:4], suites[4:7], suites[7:10], suites[10:]]
            result = MODULE.stable_partition(partition, weights)
            self.assertEqual(result, MODULE.stable_partition(partition, weights))
            flattened = [suite for shard in result for suite in shard]
            self.assertEqual(len(flattened), len(set(flattened)))
            self.assertEqual(set(flattened), set(suites))
            self.assertTrue(all(result))
            moved = any(
                suite not in result[index]
                for index, shard in enumerate(partition[:-1])
                for suite in shard
            )
            if moved:
                self.assertLessEqual(
                    max(MODULE.partition_totals(result, weights)),
                    max(MODULE.partition_totals(partition, weights)) * 0.95 + 1e-9,
                )

    def test_write_failure_is_reported_as_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = self.make_repo(directory)
            plan = repo / "plan.json"
            plan.write_text(json.dumps(self.make_plan()))
            original = plan.read_bytes()
            junit = self.timing_fixture(repo, [10, 5, 3])
            argv = [
                str(SCRIPT),
                "--plan",
                str(plan),
                "balance",
                "--repo",
                str(repo),
                "--junit",
                str(junit),
                "--write",
            ]
            stderr = io.StringIO()
            with (
                mock.patch.object(sys, "argv", argv),
                mock.patch.object(
                    pathlib.Path,
                    "write_text",
                    side_effect=OSError("injected write failure"),
                ),
                contextlib.redirect_stdout(io.StringIO()),
                contextlib.redirect_stderr(stderr),
            ):
                with self.assertRaises(SystemExit) as error:
                    MODULE.main()
            self.assertEqual(error.exception.code, 1)
            self.assertIn("injected write failure", stderr.getvalue())
            self.assertNotIn("Updated", stderr.getvalue())
            self.assertEqual(plan.read_bytes(), original)

    def test_single_move_ties_use_suite_then_worker(self):
        result = MODULE.stable_partition(
            [["C", "B", "A"], ["D"], ["E"], []],
            {"A": 90, "B": 5, "C": 5, "D": 90, "E": 90},
        )
        self.assertEqual(result, [["C", "A"], ["D", "B"], ["E"]])

    def test_cli_intake_qualifies_without_five_percent_improvement(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = self.make_repo(directory)
            plan = repo / "plan.json"
            baseline = self.make_plan()
            baseline["shards"][0]["suites"].remove(
                "ModuleSnapshotTests/ThirdSnapshotTests"
            )
            plan.write_text(json.dumps(baseline))
            junit = self.timing_fixture(repo, [100, 95, 2])
            result = self.balance_cli(repo, plan, junit, "--write")
            self.assertEqual(result.returncode, 0, result.stderr)
            report = json.loads(result.stdout)
            self.assertTrue(report["changed"])
            self.assertEqual(report["improvementPercent"], 0)
            self.assertEqual(report["movedSuites"], [])
            self.assertEqual(report["afterSeconds"], [100, 97, 0])
            _, partition = MODULE.execution_partition(MODULE.load_plan(plan), repo)
            self.assertEqual(partition[-1], [])

    def write_junit(self, path, suites):
        root = ET.Element("testsuites")
        for index, suite in enumerate(suites):
            ET.SubElement(root, "testcase", file=suite, name=f"test{index}")
        ET.ElementTree(root).write(path, encoding="utf-8", xml_declaration=True)


if __name__ == "__main__":
    unittest.main()
