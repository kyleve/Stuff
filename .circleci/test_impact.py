#!/usr/bin/env python3
"""Validate, materialize, and audit compiler-index test selection in CircleCI."""

import argparse
import json
import pathlib
import subprocess
import sys
import xml.etree.ElementTree as ET


FORMAT_VERSION = 1
SCOPES = {"all", "none", "suites"}


def current_head():
    return subprocess.run(
        ["git", "rev-parse", "HEAD"], capture_output=True, check=True, text=True
    ).stdout.strip()


def load_and_validate(path, scheme, head=None):
    try:
        selection = json.loads(path.read_text())
    except FileNotFoundError as error:
        raise ValueError(f"test-impact selection does not exist: {path}") from error
    except json.JSONDecodeError as error:
        raise ValueError(f"test-impact selection is not valid JSON: {error}") from error

    if selection.get("formatVersion") != FORMAT_VERSION:
        raise ValueError(
            f"unsupported selection formatVersion {selection.get('formatVersion')}; "
            f"expected {FORMAT_VERSION}"
        )
    expected_head = head or current_head()
    if selection.get("head") != expected_head:
        raise ValueError(
            f"selection head is {selection.get('head')!r}; checkout is {expected_head!r}"
        )
    scheme_selection = selection.get("schemes", {}).get(scheme)
    if not isinstance(scheme_selection, dict):
        raise ValueError(f"selection has no scheme named {scheme}")
    scope = scheme_selection.get("scope")
    identifiers = scheme_selection.get("identifiers")
    if scope not in SCOPES:
        raise ValueError(f"selection scope is invalid: {scope!r}")
    if not isinstance(identifiers, list) or any(
        not isinstance(identifier, str) or not identifier for identifier in identifiers
    ):
        raise ValueError("selection identifiers must be non-empty strings")
    if len(identifiers) != len(set(identifiers)):
        raise ValueError("selection identifiers contain duplicates")
    if scope == "none" and identifiers:
        raise ValueError("a none selection must not contain identifiers")
    if scope == "suites" and not identifiers:
        raise ValueError("a suites selection must contain identifiers")
    return selection, scheme_selection


def suite_is_selected(suite, identifiers):
    return any(suite == identifier or suite.startswith(identifier + "/") for identifier in identifiers)


def materialize(scheme_selection, assigned=None):
    identifiers = scheme_selection["identifiers"]
    scope = scheme_selection["scope"]
    if assigned is None:
        return identifiers
    assigned = sorted(set(assigned))
    if scope == "all":
        return assigned
    if scope == "none":
        return []
    return [suite for suite in assigned if suite_is_selected(suite, identifiers)]


def audit(selection, scheme_selection, junit, assigned=None, mode="shadow"):
    cases = []
    if junit.is_file():
        cases = list(ET.parse(junit).iterfind(".//testcase"))
    suites = sorted({case.get("file") for case in cases if case.get("file")})
    identifiers = scheme_selection["identifiers"]
    scope = scheme_selection["scope"]
    if assigned is None:
        expected = identifiers
        unexpected = [] if scope == "all" else [
            suite for suite in suites if not suite_is_selected(suite, identifiers)
        ]
    else:
        assigned = sorted(set(assigned))
        expected = assigned if scope == "all" else [
            suite for suite in assigned if suite_is_selected(suite, identifiers)
        ]
        unexpected = [suite for suite in suites if suite not in expected]
    observed = [
        identifier for identifier in expected
        if any(suite_is_selected(suite, [identifier]) for suite in suites)
    ]
    missing = sorted(set(expected) - set(observed))
    return {
        "mode": mode,
        "fallback": bool(selection.get("fallback")),
        "scope": scope,
        "selectedIdentifierCount": len(identifiers),
        "expectedIdentifierCount": len(expected),
        "executedTestCount": len(cases),
        "executedSuiteCount": len(suites),
        "selectedIdentifiersObserved": len(observed),
        "missingSelectedIdentifiers": missing,
        "unexpectedExecutedSuites": unexpected,
    }


def parse_args():
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    for name in ("validate", "materialize", "audit"):
        command = subparsers.add_parser(name)
        command.add_argument("--selection", type=pathlib.Path, required=True)
        command.add_argument("--scheme", required=True)
        if name == "materialize":
            command.add_argument("--output", type=pathlib.Path, required=True)
            command.add_argument("--assigned-file", type=pathlib.Path)
        if name == "audit":
            command.add_argument("--junit", type=pathlib.Path, required=True)
            command.add_argument("--output", type=pathlib.Path, required=True)
            command.add_argument("--assigned-file", type=pathlib.Path)
            command.add_argument("--mode", choices=("shadow", "enforce"), default="shadow")
    return parser.parse_args()


def main():
    args = parse_args()
    try:
        selection, scheme_selection = load_and_validate(args.selection, args.scheme)
        if args.command == "validate":
            print(
                f"Validated shadow test selection for {args.scheme}: "
                f"{scheme_selection['scope']}"
            )
            return
        assigned = None
        if args.assigned_file:
            assigned = [
                line.strip() for line in args.assigned_file.read_text().splitlines() if line.strip()
            ]
        if args.command == "materialize":
            identifiers = materialize(scheme_selection, assigned)
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text("".join(f"{identifier}\n" for identifier in identifiers))
            report = {
                "scope": scheme_selection["scope"],
                "selectedIdentifierCount": len(identifiers),
            }
            print("CI_TEST_IMPACT_FILTER " + json.dumps(report, separators=(",", ":")))
            return
        report = audit(selection, scheme_selection, args.junit, assigned, args.mode)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
        print("CI_TEST_IMPACT " + json.dumps(report, separators=(",", ":")))
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
