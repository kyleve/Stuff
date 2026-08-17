import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from xcode_results import test_cases


class XcodeResultsTests(unittest.TestCase):
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


if __name__ == "__main__":
    unittest.main()
