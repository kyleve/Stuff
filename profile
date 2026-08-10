#!/bin/bash
set -euo pipefail

# profile — deterministic, repeatable hot-spot report for Where's build and
# test times.
#
# It runs a clean `build-for-testing` (capturing Xcode's build-timing summary
# and any slow type-check warnings) and two test legs — the explicit
# `Stuff-iOS-Tests` scheme for the unit-test bundles, then the standalone
# `StuffSnapshotTests` scheme for the image-snapshot suite — reading
# authoritative per-test durations straight out of each .xcresult via
# xcresulttool. It then prints setup/build/test walls, the slowest build phases
# and tests, per-bundle totals, and the snapshot pipeline's own phase metadata.
# Its versioned per-suite snapshot report can be fed back to
# `./snapshot-shards balance --report` without another test run.
# `--ci-shape` gives the two schemes separate cold DerivedData, matching the
# independent CI jobs; the default shares build products for quicker iteration.
#
# The snapshot suite only runs via its own scheme: that scheme's test action
# carries the SNAPSHOT_EXPECTED_* / TZ environment pins the image comparisons
# rely on, and the capture pipeline is single-tenant, so the leg stays serial
# (xcodebuild's default — never add parallel-testing flags here; see the
# snapshot job in .github/workflows/ci.yml). The explicit unit scheme excludes
# the image bundles, whose environment-pinned dedicated scheme is their only
# test leg. `--no-snapshots` drops that leg (it adds ~10–15 min).
#
# Report only: it never fails on slow numbers, it just calls them out — but a
# failing test leg aborts the run (exit non-zero) naming the leg and tailing
# its log, so a red snapshot suite (stale references on a branch, say) reads
# as a test failure, not a profile bug.
# Absolute wall times drift run to run, but the rankings and the structure of
# the report are stable, so it's useful for spotting regressions over time.
#
# Why raw xcodebuild instead of `tuist test`? Tuist's pretty formatter
# swallows `-showBuildTimingSummary`, and the .xcresult is the most reliable,
# formatter-independent source of per-test timings. We still let Tuist own
# project generation so a run always reflects the current manifests.

DEVICE="iPhone 17"
OS="27.0"
TOP=15
TEST_THRESHOLD="0.1"   # seconds — tests at/over this are flagged as hot spots
TC_THRESHOLD=100       # milliseconds — slow type-check warn threshold
DO_BUILD=true
DO_TESTS=true
DO_SNAPSHOTS=true
CI_SHAPE=false

usage() {
    cat <<'USAGE'
Usage: ./profile [options]

Profiles Where's clean build and its test run — the unit-test bundles via the
Stuff-iOS-Tests scheme plus the image-snapshot suite via its standalone
StuffSnapshotTests scheme — then prints the hot spots.

Options:
  --build-only              Only profile the build
  --tests-only              Only profile the tests
  --no-snapshots            Skip the StuffSnapshotTests leg (saves ~10-15 min)
  --ci-shape                Use separate cold DerivedData for unit and snapshot
                            jobs, matching CI topology (default shares products)
  --device NAME             Simulator device name (default: "iPhone 17")
  --os VERSION              Simulator iOS version (default: "27.0")
  --top N                   How many slowest tests to list (default: 15)
  --test-threshold SECS     Flag tests at/over this many seconds (default: 0.1)
  --typecheck-threshold MS  Warn on type-check work over this many ms (default: 100)
  -h, --help                Show this help

Examples:
  ./profile
  ./profile --tests-only --no-snapshots --top 25 --test-threshold 0.2
  ./profile --ci-shape
  ./profile --device 'iPhone 17 Pro' --os 27.0
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        --build-only) DO_TESTS=false ;;
        --tests-only) DO_BUILD=false ;;
        --no-snapshots) DO_SNAPSHOTS=false ;;
        --ci-shape) CI_SHAPE=true ;;
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
SCHEME="Stuff-iOS-Tests"
SNAPSHOT_SCHEME="StuffSnapshotTests"
# Boot the target up front and address it by UDID: a cold simulator otherwise
# lands in the timings as build/test cost, and a name-based destination can
# resolve to a same-named device on another runtime. `./simulator` hands back
# the device this checkout owns (creating it the first time), so a run in
# another checkout can't perturb these numbers by sharing it.
SECONDS=0
SIMULATOR_UDID="$(./simulator --device "$DEVICE" --os "$OS")"
simulator_wall=$SECONDS
DESTINATION="platform=iOS Simulator,id=$SIMULATOR_UDID"

CHECKOUT_HASH="$(printf '%s' "$(pwd -P)" | shasum -a 256 | cut -c1-12)"
# Keep profiling artifacts isolated just like the checkout-owned simulator:
# concurrent clones/worktrees must not replace one another's DerivedData,
# logs, or result bundles. PROFILE_WORKDIR remains an explicit CI override.
WORKDIR="${PROFILE_WORKDIR:-${TMPDIR:-/tmp}/where-profile-$CHECKOUT_HASH}"
DERIVED="$WORKDIR/DerivedData"
SNAPSHOT_DERIVED="$DERIVED"
[ "$CI_SHAPE" = true ] && SNAPSHOT_DERIVED="$WORKDIR/SnapshotDerivedData"
BUILD_LOG="$WORKDIR/build.log"
TEST_LOG="$WORKDIR/test.log"
RESULT_BUNDLE="$WORKDIR/tests.xcresult"
TESTS_JSON="$WORKDIR/tests.json"
SNAPSHOT_BUILD_LOG="$WORKDIR/snapshot-build.log"
SNAPSHOT_TEST_LOG="$WORKDIR/snapshot-test.log"
SNAPSHOT_RESULT_BUNDLE="$WORKDIR/snapshot-tests.xcresult"
SNAPSHOT_TESTS_JSON="$WORKDIR/snapshot-tests.json"
SNAPSHOT_SUITE_REPORT="$WORKDIR/snapshot-suite-durations.json"
SNAPSHOT_TIMINGS="$WORKDIR/snapshot-timings.jsonl"
mkdir -p "$WORKDIR" && chmod 700 "$WORKDIR"

rule() { printf '%s\n' "============================================================"; }

# `$(inherited)` must reach xcodebuild literally; only $TC_THRESHOLD is ours.
# Shared by the clean unit build and the snapshot scheme's incremental
# build below — identical settings are what let the second build reuse the
# first instead of recompiling the world.
tc_flags="\$(inherited) -Xfrontend -warn-long-function-bodies=$TC_THRESHOLD -Xfrontend -warn-long-expression-type-checking=$TC_THRESHOLD"

echo "==> Regenerating project (tuist generate --no-open)"
SECONDS=0
mise exec -- tuist generate --no-open >/dev/null
generation_wall=$SECONDS

# Xcode does not expand the scheme's $(BUILT_PRODUCTS_DIR) environment value
# for command-line test runs. Resolve the profiler's isolated build-products
# directory and hand it to SwiftPM's Bundle.module accessors through the same
# TEST_RUNNER_ override as ./test. See packageResourceEnvironment in
# Project.swift for the hosted-test linking bug this works around.
UNIT_TEST_RUN_ENV=()
SNAPSHOT_TEST_RUN_ENV=("TEST_RUNNER_SNAPSHOT_TIMING=1")
SECONDS=0
BUILT_PRODUCTS_DIR="$(xcodebuild -showBuildSettings \
    -workspace "$WORKSPACE" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED" 2>/dev/null \
    | awk -F' = ' '/ BUILT_PRODUCTS_DIR = /{print $2; exit}')"
unit_build_settings_wall=$SECONDS
if [ -n "$BUILT_PRODUCTS_DIR" ]; then
    UNIT_TEST_RUN_ENV+=("TEST_RUNNER_PACKAGE_RESOURCE_BUNDLE_PATH=$BUILT_PRODUCTS_DIR")
else
    echo "warning: could not resolve BUILT_PRODUCTS_DIR; package resource" \
        "bundle lookups will fall back to the linker's placement" >&2
fi

snapshot_build_settings_wall=0
if [ "$DO_TESTS" = true ] && [ "$DO_SNAPSHOTS" = true ]; then
    SECONDS=0
    SNAPSHOT_BUILT_PRODUCTS_DIR="$(xcodebuild -showBuildSettings \
        -workspace "$WORKSPACE" \
        -scheme "$SNAPSHOT_SCHEME" \
        -destination "$DESTINATION" \
        -derivedDataPath "$SNAPSHOT_DERIVED" 2>/dev/null \
        | awk -F' = ' '/ BUILT_PRODUCTS_DIR = /{print $2; exit}')"
    snapshot_build_settings_wall=$SECONDS
    if [ -n "$SNAPSHOT_BUILT_PRODUCTS_DIR" ]; then
        SNAPSHOT_TEST_RUN_ENV+=(
            "TEST_RUNNER_PACKAGE_RESOURCE_BUNDLE_PATH=$SNAPSHOT_BUILT_PRODUCTS_DIR"
        )
    else
        echo "warning: could not resolve snapshot BUILT_PRODUCTS_DIR; package resource" \
            "bundle lookups will fall back to the linker's placement" >&2
    fi
fi

if [ "$DO_BUILD" = true ]; then
    echo "==> Clean build-for-testing on $DEVICE / iOS $OS (cold build)"
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
        echo "==> Running unit tests (test-without-building, reuses the build above)"
    else
        # `test` builds then tests, so the wall below includes compilation
        # (a full cold build on an empty DerivedData) — label it accordingly.
        TEST_ACTION="test"
        TEST_WALL_LABEL="build+test wall"
        echo "==> Running unit tests (build + test) on $DEVICE / iOS $OS"
    fi
    rm -rf "$RESULT_BUNDLE"
    SECONDS=0
    set +e
    env ${UNIT_TEST_RUN_ENV[@]+"${UNIT_TEST_RUN_ENV[@]}"} \
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
        echo "error: unit-test leg ($SCHEME) failed (exit $test_status). Tail of $TEST_LOG:" >&2
        tail -n 40 "$TEST_LOG" >&2
        exit "$test_status"
    fi
    xcrun xcresulttool get test-results tests --path "$RESULT_BUNDLE" >"$TESTS_JSON"
    TEST_JSON_PATHS="$TESTS_JSON"
    WALL_SUMMARY="$TEST_WALL_LABEL: ${test_wall}s"

    if [ "$DO_SNAPSHOTS" = true ]; then
        if [ "$DO_BUILD" = true ]; then
            if [ "$CI_SHAPE" = true ]; then
                SNAPSHOT_BUILD_ACTION=(clean build-for-testing)
                SNAPSHOT_BUILD_LABEL="cold, separate DerivedData matching CI"
            else
                # Same DerivedData, destination, and flags as the clean unit
                # build above, so this reuses shared products while adding the
                # image bundles.
                SNAPSHOT_BUILD_ACTION=(build-for-testing)
                SNAPSHOT_BUILD_LABEL="incremental, reuses the unit build"
            fi
            echo "==> ${SNAPSHOT_BUILD_ACTION[*]} $SNAPSHOT_SCHEME ($SNAPSHOT_BUILD_LABEL)"
            SECONDS=0
            set +e
            xcodebuild "${SNAPSHOT_BUILD_ACTION[@]}" \
                -workspace "$WORKSPACE" \
                -scheme "$SNAPSHOT_SCHEME" \
                -destination "$DESTINATION" \
                -derivedDataPath "$SNAPSHOT_DERIVED" \
                OTHER_SWIFT_FLAGS="$tc_flags" \
                >"$SNAPSHOT_BUILD_LOG" 2>&1
            snapshot_build_status=$?
            set -e
            snapshot_build_wall=$SECONDS
            if [ "$snapshot_build_status" -ne 0 ]; then
                echo "error: snapshot build ($SNAPSHOT_SCHEME) failed (exit $snapshot_build_status). Tail of $SNAPSHOT_BUILD_LOG:" >&2
                tail -n 30 "$SNAPSHOT_BUILD_LOG" >&2
                exit "$snapshot_build_status"
            fi
            echo "    snapshot build ($SNAPSHOT_BUILD_LABEL): ${snapshot_build_wall}s"
            SNAPSHOT_TEST_ACTION="test-without-building"
            echo "==> Running snapshot tests (test-without-building, $SNAPSHOT_SCHEME scheme — serial by design, ~10-15 min)"
        else
            SNAPSHOT_TEST_ACTION="test"
            echo "==> Running snapshot tests (build + test, $SNAPSHOT_SCHEME scheme — serial by design, ~10-15 min)"
        fi
        rm -rf "$SNAPSHOT_RESULT_BUNDLE"
        SECONDS=0
        set +e
        env ${SNAPSHOT_TEST_RUN_ENV[@]+"${SNAPSHOT_TEST_RUN_ENV[@]}"} \
            xcodebuild "$SNAPSHOT_TEST_ACTION" \
            -workspace "$WORKSPACE" \
            -scheme "$SNAPSHOT_SCHEME" \
            -destination "$DESTINATION" \
            -derivedDataPath "$SNAPSHOT_DERIVED" \
            -resultBundlePath "$SNAPSHOT_RESULT_BUNDLE" \
            >"$SNAPSHOT_TEST_LOG" 2>&1
        snapshot_status=$?
        set -e
        snapshot_wall=$SECONDS
        if [ "$snapshot_status" -ne 0 ]; then
            echo "error: snapshot-test leg ($SNAPSHOT_SCHEME) failed (exit $snapshot_status). Tail of $SNAPSHOT_TEST_LOG:" >&2
            tail -n 40 "$SNAPSHOT_TEST_LOG" >&2
            echo "note: a red snapshot leg usually means failed image comparisons (e.g. stale references on this branch), not a profile bug — rerun with --no-snapshots to profile without it." >&2
            exit "$snapshot_status"
        fi
        xcrun xcresulttool get test-results tests --path "$SNAPSHOT_RESULT_BUNDLE" >"$SNAPSHOT_TESTS_JSON"
        ./snapshot-shards report \
            --xcresult "$SNAPSHOT_RESULT_BUNDLE" \
            --output "$SNAPSHOT_SUITE_REPORT"
        : >"$SNAPSHOT_TIMINGS"
        grep -o 'SNAPSHOT_TIMING {.*}' "$SNAPSHOT_TEST_LOG" 2>/dev/null \
            | sed 's/^SNAPSHOT_TIMING //' >>"$SNAPSHOT_TIMINGS" || true
        echo
        rule
        echo "SNAPSHOT CAPTURE PHASES"
        rule
        LINES="$SNAPSHOT_TIMINGS" python3 - <<'PY'
import collections, json, os, sys

rows = [json.loads(line) for line in open(os.environ['LINES']) if line.strip()]
if not rows:
    print('  (no timing lines found)')
    sys.exit(0)

grand = sum(row['total'] for row in rows)
phases = collections.Counter()
for row in rows:
    phases.update(row['phases'])

print(f'  {len(rows)} captures, {grand:.1f}s total, {grand / len(rows):.3f}s per image\n')
print(f"  {'phase':20s} {'total':>9s} {'share':>7s} {'mean':>9s}")
for phase, seconds in phases.most_common():
    print(f'  {phase:20s} {seconds:8.2f}s {100 * seconds / grand:6.1f}% '
          f'{seconds / len(rows):8.3f}s')

def print_counts(title, key):
    counts = collections.Counter(row.get(key, 'unknown') for row in rows)
    print(f'\n  {title}:')
    for value, count in sorted(counts.items(), key=lambda item: (-item[1], item[0])):
        print(f'    {count:4d}  {value}')

print_counts('sizing', 'sizing')
print_counts('measurement readiness', 'measurementReadiness')
print_counts('capture settle', 'captureSettle')

print('\n  intrinsic measurement by readiness:')
for readiness in sorted(set(row.get('measurementReadiness', 'unknown') for row in rows)):
    selected = [row for row in rows if row.get('measurementReadiness', 'unknown') == readiness]
    seconds = sum(row['phases'].get('intrinsicMeasure', 0) for row in selected)
    print(f'    {seconds:8.2f}s  {readiness} ({len(selected)} captures)')

passes = [row['settlePasses'] for row in rows]
print(f'\n  settle passes: min {min(passes)}, max {max(passes)}, '
      f'mean {sum(passes) / len(passes):.1f}')
print('\n  slowest captures:')
for row in sorted(rows, key=lambda row: -row['total'])[:8]:
    print(f"    {row['total']:6.3f}s  {row['id']}")
PY
        TEST_JSON_PATHS="$TESTS_JSON:$SNAPSHOT_TESTS_JSON"
        WALL_SUMMARY="$TEST_WALL_LABEL: ${test_wall}s (unit) + ${snapshot_wall}s (snapshot)"
    fi

    echo
    rule
    echo "TEST HOT SPOTS  —  $WALL_SUMMARY"
    rule
    # Best-effort parse: warn and continue if the xcresult schema shifts.
    set +e
    TESTS_JSON="$TEST_JSON_PATHS" TOP="$TOP" TEST_THRESHOLD="$TEST_THRESHOLD" python3 - <<'PY'
import json, os, sys
from collections import defaultdict


def main():
    cases = []  # (bundle, name, seconds)

    def walk(node, bundle):
        nt = node.get('nodeType')
        if nt == 'Unit test bundle':
            bundle = node.get('name', bundle)
        # Exclude skipped parameterized cases from the real run counts.
        if nt == 'Test Case' and node.get('result') != 'Skipped':
            cases.append((bundle, node.get('name', '?'),
                          float(node.get('durationInSeconds') or 0)))
        for child in node.get('children', []):
            walk(child, bundle)

    # One JSON per test leg (unit + snapshot), colon-separated; the bundles
    # are disjoint across legs, so the merged rows stay per-bundle exact.
    for path in os.environ['TESTS_JSON'].split(':'):
        data = json.load(open(path))
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

rule
echo "PROFILE WALLS"
rule
echo "  simulator resolve/boot: ${simulator_wall}s"
echo "  project generation: ${generation_wall}s"
echo "  unit build settings: ${unit_build_settings_wall}s"
if [ "$DO_TESTS" = true ] && [ "$DO_SNAPSHOTS" = true ]; then
    echo "  snapshot build settings: ${snapshot_build_settings_wall}s"
fi
if [ "$DO_BUILD" = true ]; then
    echo "  cold unit build: ${build_wall}s"
fi
if [ "$DO_TESTS" = true ]; then
    echo "  unit $TEST_WALL_LABEL: ${test_wall}s"
    if [ "$DO_SNAPSHOTS" = true ]; then
        if [ "$DO_BUILD" = true ]; then
            echo "  snapshot build ($SNAPSHOT_BUILD_LABEL): ${snapshot_build_wall}s"
        fi
        echo "  snapshot execution wall: ${snapshot_wall}s"
    fi
fi
echo

echo "Logs and result bundles: $WORKDIR"
