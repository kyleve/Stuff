import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from xcode_results import test_cases, test_duration


class XcodeResultsTests(unittest.TestCase):
    def test_sums_argument_and_repetition_leaves_without_counting_parent_means(self):
        node = {
            "nodeType": "Test Case",
            "name": "values(_:)",
            "durationInSeconds": 2,
            "children": [
                {"nodeType": "Arguments", "durationInSeconds": 1.25},
                {
                    "nodeType": "Arguments",
                    "durationInSeconds": 3,
                    "children": [
                        {"nodeType": "Repetition", "durationInSeconds": 2.75},
                        {"nodeType": "Repetition", "durationInSeconds": 3.25},
                    ],
                },
                {"nodeType": "Expected Failure", "durationInSeconds": 100},
                "unknown child",
            ],
        }

        cases = list(test_cases({"testNodes": [node]}))

        self.assertEqual(len(cases), 1)
        self.assertEqual(cases[0].name, "values(_:)")
        self.assertEqual(cases[0].duration_seconds, 7.25)

    def test_precise_seconds_take_precedence_over_rounded_display_time(self):
        self.assertEqual(
            test_duration({"durationInSeconds": 9.272, "duration": "9s"}), 9.272
        )
        self.assertEqual(test_duration({"duration": "1m 12.5s"}), 72.5)
        self.assertEqual(test_duration({"duration": "320ms"}), 0.32)
        self.assertEqual(test_duration({"duration": "1s invalid"}), 0)
        for value in [None, True, "bad", float("nan"), float("inf"), -1]:
            with self.subTest(value=value):
                self.assertEqual(test_duration({"durationInSeconds": value}), 0)

    def test_skipped_arguments_do_not_add_execution_time(self):
        self.assertEqual(
            test_duration(
                {
                    "durationInSeconds": 4,
                    "children": [
                        {
                            "nodeType": "Arguments",
                            "result": "Skipped",
                            "durationInSeconds": 7,
                        },
                        {
                            "nodeType": "Arguments",
                            "result": "Passed",
                            "durationInSeconds": 1,
                        },
                    ],
                }
            ),
            1,
        )

    def test_walks_bundle_suite_and_case_nodes(self):
        document = {
            "testNodes": [
                {
                    "nodeType": "Unit test bundle",
                    "name": "WhereCoreTests",
                    "children": [
                        {
                            "nodeType": "Test Suite",
                            "name": "StoreTests",
                            "children": [
                                {
                                    "nodeType": "Test Case",
                                    "name": "loads()",
                                    "nodeIdentifier": "StoreTests/loads()",
                                    "result": "Passed",
                                    "durationInSeconds": "0.125",
                                }
                            ],
                        }
                    ],
                }
            ]
        }

        case = list(test_cases(document))[0]

        self.assertEqual(case.bundle, "WhereCoreTests")
        self.assertEqual(case.suites, ("StoreTests",))
        self.assertEqual(case.result, "passed")
        self.assertEqual(case.duration_seconds, 0.125)
        self.assertEqual(
            case.only_testing_identifier,
            "WhereCoreTests/StoreTests/loads()",
        )
        self.assertEqual(case.suite_identifier, "WhereCoreTests/StoreTests")

    def test_falls_back_to_suite_chain_when_node_identifier_is_absent(self):
        document = {
            "testNodes": [
                {
                    "nodeType": "Test Suite",
                    "name": "Outer",
                    "children": [
                        {
                            "nodeType": "Test Suite",
                            "name": "Inner",
                            "children": [
                                {
                                    "nodeType": "Test Case",
                                    "name": "fails()",
                                    "result": "Failed",
                                    "durationInSeconds": "not-a-number",
                                }
                            ],
                        }
                    ],
                }
            ]
        }

        case = list(test_cases(document))[0]

        self.assertEqual(case.only_testing_identifier, "Outer/Inner/fails()")
        self.assertEqual(case.duration_seconds, 0.0)

    def test_tolerates_unknown_nodes_parameterized_names_and_missing_fields(self):
        document = {
            "testNodes": [
                {
                    "nodeType": "Future grouping kind",
                    "name": "ignored",
                    "children": [
                        {
                            "nodeType": "Test Case",
                            "name": "values(_:) (input: 7)",
                            "durationInSeconds": None,
                        },
                        {"nodeType": "Test Case"},
                        "unexpected scalar child",
                    ],
                }
            ]
        }

        cases = list(test_cases(document))

        self.assertEqual([case.name for case in cases], ["values(_:) (input: 7)", "?"])
        self.assertEqual(cases[0].only_testing_identifier, "values(_:) (input: 7)")
        self.assertEqual(cases[0].duration_seconds, 0.0)
        self.assertEqual(cases[1].result, "")

        self.assertEqual(list(test_cases([])), [])
        self.assertEqual(list(test_cases({"testNodes": {"future": "shape"}})), [])


if __name__ == "__main__":
    unittest.main()
