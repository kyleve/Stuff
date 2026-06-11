#!/bin/bash
set -euo pipefail

# profile — deterministic, repeatable hot-spot report for Where's build and
# test times.
#
# It runs a clean `build-for-testing` (capturing Xcode's build-timing summary
# and any slow type-check warnings) and a test pass (reading authoritative
# per-test durations straight out of the .xcresult via xcresulttool), then
# prints the slowest build phases, the slowest tests, and per-bundle totals.
#
# Report only: it never fails on slow numbers, it just calls them out.
# Absolute wall times drift run to run, but the rankings and the structure of
# the report are stable, so it's useful for spotting regressions over time.
#
# Why raw xcodebuild instead of `tuist test`? Tuist's pretty formatter
# swallows `-showBuildTimingSummary`, and the .xcresult is the most reliable,
# formatter-independent source of per-test timings. We still let Tuist own
# project generation so a run always reflects the current manifests.

DEVICE="iPhone 17"
OS="26.2"
TOP=15
TEST_THRESHOLD="0.1"   # seconds — tests at/over this are flagged as hot spots
TC_THRESHOLD=100       # milliseconds — slow type-check warn threshold
DO_BUILD=true
DO_TESTS=true

usage() {
    cat <<'USAGE'
Usage: ./profile [options]

Profiles Where's clean build and its test run, then prints the hot spots.

Options:
  --build-only              Only profile the build
  --tests-only              Only profile the tests
  --device NAME             Simulator device name (default: "iPhone 17")
  --os VERSION              Simulator iOS version (default: "26.2")
  --top N                   How many slowest tests to list (default: 15)
  --test-threshold SECS     Flag tests at/over this many seconds (default: 0.1)
  --typecheck-threshold MS  Warn on type-check work over this many ms (default: 100)
  -h, --help                Show this help

Examples:
  ./profile
  ./profile --tests-only --top 25 --test-threshold 0.2
  ./profile --device 'iPhone 17 Pro' --os 26.2
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        --build-only) DO_TESTS=false ;;
        --tests-only) DO_BUILD=false ;;
        --device) shift; DEVICE="${1:?--device requires a value}" ;;
        --os) shift; OS="${1:?--os requires a value}" ;;
        --top) shift; TOP="${1:?--top requires a value}" ;;
        --test-threshold) shift; TEST_THRESHOLD="${1:?--test-threshold requires a value}" ;;
        --typecheck-threshold) shift; TC_THRESHOLD="${1:?--typecheck-threshold requires a value}" ;;
        -h|--help) usage; exit 0 ;;
        *) echo "error: unknown option '$1' (see ./profile --help)" >&2; exit 1 ;;
    esac
    shift
done

cd "$(dirname "$0")"

WORKSPACE="Stuff.xcworkspace"
SCHEME="Stuff-Workspace"
DESTINATION="platform=iOS Simulator,name=$DEVICE,OS=$OS"

WORKDIR="${TMPDIR:-/tmp}/where-profile"
DERIVED="$WORKDIR/DerivedData"
BUILD_LOG="$WORKDIR/build.log"
TEST_LOG="$WORKDIR/test.log"
RESULT_BUNDLE="$WORKDIR/tests.xcresult"
TESTS_JSON="$WORKDIR/tests.json"
mkdir -p "$WORKDIR"

rule() { printf '%s\n' "============================================================"; }

echo "==> Regenerating project (tuist generate --no-open)"
mise exec -- tuist generate --no-open >/dev/null

if [ "$DO_BUILD" = true ]; then
    echo "==> Clean build-for-testing on $DEVICE / iOS $OS (cold build)"
    # `$(inherited)` must reach xcodebuild literally; only $TC_THRESHOLD is ours.
    tc_flags="\$(inherited) -Xfrontend -warn-long-function-bodies=$TC_THRESHOLD -Xfrontend -warn-long-expression-type-checking=$TC_THRESHOLD"
    SECONDS=0
    set +e
    xcodebuild clean build-for-testing \
        -workspace "$WORKSPACE" \
        -scheme "$SCHEME" \
        -destination "$DESTINATION" \
        -derivedDataPath "$DERIVED" \
        -showBuildTimingSummary \
        OTHER_SWIFT_FLAGS="$tc_flags" \
        >"$BUILD_LOG" 2>&1
    build_status=$?
    set -e
    build_wall=$SECONDS
    if [ "$build_status" -ne 0 ]; then
        echo "error: build failed (exit $build_status). Tail of $BUILD_LOG:" >&2
        tail -n 30 "$BUILD_LOG" >&2
        exit "$build_status"
    fi
    echo
    rule
    echo "BUILD HOT SPOTS  —  cold build wall: ${build_wall}s"
    rule
    # Parsing is best-effort: if xcodebuild's log format ever shifts, warn and
    # keep going rather than aborting the run with a traceback.
    set +e
    BUILD_LOG="$BUILD_LOG" TC_THRESHOLD="$TC_THRESHOLD" python3 - <<'PY'
import os, re, sys


def main():
    log = open(os.environ['BUILD_LOG'], errors='replace').read()

    phase_re = re.compile(r'^(.+?) \((\d+) tasks?\) \| ([\d.]+) seconds$', re.M)
    phases = [(m.group(1).strip(), int(m.group(2)), float(m.group(3)))
              for m in phase_re.finditer(log)]
    if phases:
        total = sum(p[2] for p in phases)
        print("Build phases (summed task-time across cores; wall is lower thanks to")
        print("parallelism — use the shares, not the absolute seconds):")
        for name, n, secs in sorted(phases, key=lambda x: -x[2]):
            pct = 100 * secs / total if total else 0
            print(f"  {secs:8.2f}s  {pct:4.0f}%  {name} ({n})")
    else:
        print("  (no build-timing summary found — was this a no-op incremental build?)")

    limit = int(os.environ['TC_THRESHOLD'])
    tc = re.findall(r'(/[^:\n]+:\d+:\d+): warning: (.*?took (\d+)ms to type-check.*)$',
                    log, re.M)
    print()
    if tc:
        print(f"Slow type-check sites (limit {limit}ms):")
        for loc, _msg, ms in sorted(tc, key=lambda x: -int(x[2])):
            short = re.sub(r'^.*?/((?:Where|Shared)/)', r'\1', loc)
            print(f"  {int(ms):6d}ms  {short}")
    else:
        print(f"Slow type-check sites (limit {limit}ms): none — no expression or")
        print("function body exceeded the threshold.")


try:
    main()
except Exception as exc:  # never hard-fail a reporting tool
    print(f"warning: couldn't parse build timing from {os.environ['BUILD_LOG']} ({exc})",
          file=sys.stderr)
    sys.exit(1)
PY
    set -e
    echo
fi

if [ "$DO_TESTS" = true ]; then
    if [ "$DO_BUILD" = true ]; then
        TEST_ACTION="test-without-building"
        TEST_WALL_LABEL="test-execution wall"
        echo "==> Running tests (test-without-building, reuses the build above)"
    else
        # `test` builds then tests, so the wall below includes compilation
        # (a full cold build on an empty DerivedData) — label it accordingly.
        TEST_ACTION="test"
        TEST_WALL_LABEL="build+test wall"
        echo "==> Running tests (build + test) on $DEVICE / iOS $OS"
    fi
    rm -rf "$RESULT_BUNDLE"
    SECONDS=0
    set +e
    xcodebuild "$TEST_ACTION" \
        -workspace "$WORKSPACE" \
        -scheme "$SCHEME" \
        -destination "$DESTINATION" \
        -derivedDataPath "$DERIVED" \
        -resultBundlePath "$RESULT_BUNDLE" \
        >"$TEST_LOG" 2>&1
    test_status=$?
    set -e
    test_wall=$SECONDS
    if [ "$test_status" -ne 0 ]; then
        echo "error: tests failed (exit $test_status). Tail of $TEST_LOG:" >&2
        tail -n 40 "$TEST_LOG" >&2
        exit "$test_status"
    fi
    xcrun xcresulttool get test-results tests --path "$RESULT_BUNDLE" >"$TESTS_JSON"
    echo
    rule
    echo "TEST HOT SPOTS  —  ${TEST_WALL_LABEL}: ${test_wall}s"
    rule
    # Best-effort parse: warn and continue if the xcresult schema shifts.
    set +e
    TESTS_JSON="$TESTS_JSON" TOP="$TOP" TEST_THRESHOLD="$TEST_THRESHOLD" python3 - <<'PY'
import json, os, sys
from collections import defaultdict


def main():
    data = json.load(open(os.environ['TESTS_JSON']))
    cases = []  # (bundle, name, seconds)

    def walk(node, bundle):
        nt = node.get('nodeType')
        if nt == 'Unit test bundle':
            bundle = node.get('name', bundle)
        if nt == 'Test Case':
            cases.append((bundle, node.get('name', '?'),
                          float(node.get('durationInSeconds') or 0)))
        for child in node.get('children', []):
            walk(child, bundle)

    for n in data.get('testNodes', []):
        walk(n, '?')

    top = int(os.environ['TOP'])
    thr = float(os.environ['TEST_THRESHOLD'])
    total = sum(d for _, _, d in cases)
    print(f"{len(cases)} tests, summed self-time {total:.2f}s")

    print()
    print(f"Slowest {top} tests:")
    for b, n, d in sorted(cases, key=lambda x: -x[2])[:top]:
        flag = '  <== over threshold' if d >= thr else ''
        print(f"  {d:7.3f}s  {b} / {n}{flag}")

    by = defaultdict(lambda: [0.0, 0])
    for b, _n, d in cases:
        by[b][0] += d
        by[b][1] += 1
    print()
    print("Per-bundle self-time:")
    for b, (d, c) in sorted(by.items(), key=lambda x: -x[1][0]):
        print(f"  {d:7.3f}s  {b} ({c} tests)")

    over = [c for c in cases if c[2] >= thr]
    print()
    if over:
        print(f"{len(over)} test(s) at/over the {thr}s threshold (flagged above).")
    else:
        print(f"No tests at/over the {thr}s threshold.")


try:
    main()
except Exception as exc:  # never hard-fail a reporting tool
    print(f"warning: couldn't parse test results from {os.environ['TESTS_JSON']} ({exc})",
          file=sys.stderr)
    sys.exit(1)
PY
    set -e
    echo
fi

echo "Logs and result bundle: $WORKDIR"
