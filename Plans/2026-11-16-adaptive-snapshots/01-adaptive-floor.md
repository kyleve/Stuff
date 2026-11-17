# 01 — Remeasure adaptive MainTabs settling

- Status: executing
- Depends on: None
- Shared requirements and exclusions: [Overview](README.md)

## Deliverable and method

Resolve Q-01 for R-01–R-04. Preserve X-01–X-03.
Only `MainTabs.adaptiveSnapshot` is selected: 39 of 61 MainTabs captures. Other cases keep their policies.
Collect a baseline at 1.5s with preparation subphase timers from plan 02.
Test 0.5s first and 0.25s only if the first value passes unchanged references and review diagnostics.
Repeat the selected value in a separate invocation. If either candidate fails, retain the last proven value or restore 1.5s.
Keep `.settledAtLeast`, both annotation parses, the 120ms anchored pixel proof, native scene policy, timeouts, and configuration coverage.

## Design

The existing readiness hook awaits `DuoLayoutSnapshotFixture.prepare()` before settling. Change only the existing duration argument:

```swift
// Existing API; the selected duration requires measured evidence.
settle: .settledAtLeast(minDuration: measuredFloor)
```

No new architecture or data flow is needed. The comment beside the declaration records the measured runtime and reason the floor remains.

## Steps and verification

1. Run the baseline from repository root: `./test --no-generate --only WhereUISnapshotTests/MainTabsSnapshotTests --timings --review --record never`.
2. Run the same matrix for each candidate. Subsequent snapshot-only runs can use `--skip-host-tests` because the baseline owns the applicable host checks.
3. Compare all 61 capture identities, pixel counts, sizing, tile counts, and diagnostic regions. Review changed diagnostics against the baseline; never widen tolerances.
4. Repeat the selected value without rebuilding only if the products contain the selected source.
5. Remove temporary profiling code. Run final affected coverage with timings and no review for comparison with the parent full profile. Run additional image/unit coverage only if plan 02 changes shared fixture behavior.
6. Independently review the complete parent-to-head diff and publish through `gh stack`.

Require no retries, passing references, and measurable reduction. A negative experiment is valid evidence, with the original floor restored.
Full image coverage is required if retained changes affect the shared renderer or application appearance; this declaration alone needs the complete MainTabs matrix.

## Recovery and record

Restore only task-owned edits after a failed candidate. Preserve the unrelated untracked simple-english skill.
Raw logs stay outside Git; dated measurements and conclusions belong here.

## Resume point

Collect the focused baseline, then test 0.5s.
