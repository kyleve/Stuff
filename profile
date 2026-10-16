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

