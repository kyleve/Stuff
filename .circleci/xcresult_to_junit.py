#!/usr/bin/env python3
"""Convert Xcode 27 test result bundles into CircleCI-compatible JUnit XML."""

import json
import pathlib
import subprocess
import sys
import xml.etree.ElementTree as ET


def duration(node):
    value = node.get("duration", 0)
    if isinstance(value, (int, float)):
        return float(value)
    try:
        return float(str(value).removesuffix("s"))
    except ValueError:
        return 0.0


def test_cases_in(result):
    completed = subprocess.run(
        ["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", str(result)],
        capture_output=True,
        check=False,
        text=True,
    )
    if completed.returncode != 0:
        print(f"warning: could not read {result}: {completed.stderr.strip()}")
        return []

    test_cases = []

    def walk(node, bundle="Xcode", suite="Tests"):
        kind = node.get("nodeType", "")
        name = node.get("name", "")
        if kind == "Unit test bundle":
            bundle = name
        elif kind == "Test Suite":
            suite = name
        elif kind == "Test Case":
            test_cases.append((bundle, suite, name, node.get("result", "Unknown"), duration(node)))
        for child in node.get("children", []):
            walk(child, bundle, suite)

    for root in json.loads(completed.stdout).get("testNodes", []):
        walk(root)
    return test_cases


def main():
    if len(sys.argv) != 3:
        raise SystemExit(f"usage: {sys.argv[0]} XCRESULT_DIRECTORY OUTPUT_XML")

    input_directory = pathlib.Path(sys.argv[1])
    output = pathlib.Path(sys.argv[2])
    test_cases = [
        case
        for result in sorted(input_directory.glob("*.xcresult"))
        for case in test_cases_in(result)
    ]

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
                name=name,
                time=f"{elapsed:.3f}",
            )
            if result.lower() == "failed":
                ET.SubElement(test_case, "failure", message="Failed; see the xcresult artifact")
            elif result.lower() == "skipped":
                ET.SubElement(test_case, "skipped")

    output.parent.mkdir(parents=True, exist_ok=True)
    ET.ElementTree(suites).write(output, encoding="utf-8", xml_declaration=True)
    print(f"Exported {len(test_cases)} test results to {output}")


if __name__ == "__main__":
    main()
