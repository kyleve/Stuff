#!/usr/bin/env python3
"""Tests for suite-level snapshot shard validation."""

import importlib.util
import pathlib
import unittest


SCRIPT = pathlib.Path(__file__).with_name("shard_suites.py")
SPEC = importlib.util.spec_from_file_location("shard_suites", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ShardTests(unittest.TestCase):
    def test_accepts_a_non_empty_two_way_partition(self):
        suites = ["Bundle/First", "Bundle/Second", "Bundle/Third"]

        MODULE.validate_partition(suites, [[suites[0], suites[2]], [suites[1]]])

    def test_rejects_an_empty_shard(self):
        with self.assertRaisesRegex(ValueError, "assigned no suites"):
            MODULE.validate_partition(
                ["Bundle/First", "Bundle/Second"],
                [["Bundle/First", "Bundle/Second"], []],
            )

    def test_rejects_an_overlapping_partition(self):
        with self.assertRaisesRegex(ValueError, "overlap"):
            MODULE.validate_partition(
                ["Bundle/First", "Bundle/Second"],
                [["Bundle/First"], ["Bundle/First", "Bundle/Second"]],
            )


if __name__ == "__main__":
    unittest.main()
