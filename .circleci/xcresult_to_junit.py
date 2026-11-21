#!/usr/bin/env python3
"""Convert Xcode 27 test result bundles into CircleCI-compatible JUnit XML."""

import argparse
from functools import cache
import json
import pathlib
import subprocess
import sys
import xml.etree.ElementTree as ET


sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "Tools"))

from grouped_tests import GROUPED_BUNDLE, GroupedTestSuites
from xcode_results import test_duration


REPOSITORY = pathlib.Path(__file__).resolve().parents[1]


def duration(node):
    return test_duration(node)


def test_cases_in(result, grouped_suites):
    completed = subprocess.run(
        [
            "xcrun",
            "xcresulttool",
            "get",
            "test-results",
            "tests",
            "--path",
            str(result),
        ],
        capture_output=True,
        check=False,
        text=True,
    )
    if completed.returncode != 0:
        print(f"warning: could not read {result}: {completed.stderr.strip()}")
        return []

    test_cases = []

    def walk(node, bundle="Xcode", suite="Tests", logical_suites=None):
        kind = node.get("nodeType", "")
        name = node.get("name", "")
        if kind == "Unit test bundle":
            bundle = name
            logical_suites = grouped_suites() if name == GROUPED_BUNDLE else None
        elif kind == "Test Suite":
            suite = name
        elif kind == "Test Case":
            if logical_suites is not None:
                bundle = logical_suites.logical_bundle(node["nodeIdentifier"])
            test_cases.append(
                (bundle, suite, name, node.get("result", "Unknown"), duration(node))
            )
        for child in node.get("children", []):
            walk(child, bundle, suite, logical_suites)

    for root in json.loads(completed.stdout).get("testNodes", []):
        walk(root)
    return test_cases


def write_junit(test_cases, output):
    suites = ET.Element("testsuites")
    grouped = {}
    for case in test_cases:
        grouped.setdefault((case[0], case[1]), []).append(case)
    for (bundle, suite_name), cases in sorted(grouped.items()):
        failures = sum(case[3].lower() == "failed" for case in cases)
        skipped = sum(case[3].lower() == "skipped" for case in cases)
        suite = ET.SubElement(
            suites,
            "testsuite",
            name=f"{bundle}.{suite_name}",
            tests=str(len(cases)),
            failures=str(failures),
            skipped=str(skipped),
            time=f"{sum(case[4] for case in cases):.3f}",
        )
        for _, _, name, result, elapsed in cases:
            test_case = ET.SubElement(
                suite,
                "testcase",
                classname=f"{bundle}.{suite_name}",
                file=f"{bundle}/{suite_name}",
                name=name,
                time=f"{elapsed:.3f}",
            )
            if result.lower() == "failed":
                ET.SubElement(
                    test_case, "failure", message="Failed; see the xcresult artifact"
                )
            elif result.lower() == "skipped":
                ET.SubElement(test_case, "skipped")

    output.parent.mkdir(parents=True, exist_ok=True)
    ET.ElementTree(suites).write(output, encoding="utf-8", xml_declaration=True)
    print(f"Exported {len(test_cases)} test results to {output}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input_directory", type=pathlib.Path)
    parser.add_argument("output", type=pathlib.Path)
    parser.add_argument("--test-artifact-manifest", type=pathlib.Path)
    args = parser.parse_args()

    @cache
    def grouped_suites():
        return GroupedTestSuites.from_manifest_or_repository(
            REPOSITORY, args.test_artifact_manifest
        )

    test_cases = [
        case
        for result in sorted(args.input_directory.glob("*.xcresult"))
        for case in test_cases_in(result, grouped_suites)
    ]
    write_junit(test_cases, args.output)


if __name__ == "__main__":
    main()
