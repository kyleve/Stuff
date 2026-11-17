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
Keep `.settledAtLeast`, both annotation parses, the 120ms anchored pixel proof, native scene policy, timeout derivation, and configuration coverage. The effective timeout changes with the floor, as documented below.

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

The selected 0.5s policy passes its clean repetition and independent review. Publish the change and dispatch the manual CI gates on the final tip.

## Execution record

- Baseline with temporary timers and review diagnostics: 61 captures, 165.948s total, 130.733s adaptive, and 65.605s adaptive settling; zero retries.
- The 0.5s candidate passes all 61 captures without retries. Total capture time is 125.385s; adaptive capture time is 89.960s and settling is 25.352s. All identities, pixel counts, sizing, and tiles match. Two larger diagnostic rows shrink by 21 and 62 pixels, with unchanged maximum channel deltas and smaller regions. Other larger diagnostics match. The 0.25s candidate is running next.

- The 0.25s candidate passes the normal reference tolerances, but fails this experiment's stricter diagnostic criterion: 13 captures gain differences above one channel step, including new maximum deltas of 2–6. Adaptive settling falls to 19.117s, but comparison grows from 12.758s at 0.5s to 23.818s. Total capture time is 130.584s, slower than the 0.5s trial. Reject 0.25s and retain 0.5s for repetition.
- All temporary timers, the callback recorder, and the isolated probe are removed. The only retained Swift change is the duration declaration and its dated explanation in MainTabs.swift. Repeat the full MainTabs matrix at 0.5s with the final source.

- The clean 0.5s repetition passes one test and all 61 captures without retries. Total capture time is 126.227s; adaptive capture time is 91.037s, with 25.424s settling. It saves 39.721s (23.94%) versus the review-enabled baseline; the initial 0.5s trial saves 40.563s (24.44%). The 22 unchanged captures total 35.215s before and 35.190s in the repeat.
- Four repeat diagnostics differ from the local baseline by −39, −21, −62, and +27 pixels. All 18 repeat diagnostics above one channel step exactly match successful parent CI job 4427, execution 3, including the +27-pixel book variant. No new reference or tolerance is used.
- A temporary `bookPixelProbe()` test alternates 1.5s and 0.5s across six fresh-world PNG captures. All six 2853×2007 PNGs are byte-identical (SHA-256 `eb2a2a95c4136be4ed2d0561a95bc865fea43bb5c717d566eb174f795d96926f`). Independent review also inspected the loaded book image. The probe is removed after validation.

## Review correction: derived timeout

Independent review identified that the original promise to preserve timeouts was incorrect. `SnapshotSettleTimeoutPolicy.maximumDuration(for:)` adds 2.5s to a raised floor. The selected 0.5s floor therefore changes readiness and observed-motion ceilings from 4s to 3s locally, and from 8s to 6s with CI's multiplier of 2. The starvation cap remains four times that ceiling and therefore also changes. Preparation timeout failures still abort without retry.

Decision: retain the existing derivation and explicitly accept the shorter effective ceilings with this fixture policy. No framework API or global default changes. The maximum observed local preparation is 1.376s in the baseline, 1.308s in the first 0.5s run, and 1.313s in the clean repeat. These samples do not prove behavior under every slow CI condition. Run the full manual CI gate on the published tip and report its status; do not claim the old timeout budget is preserved. The source comment and PR must retain this review finding and decision.
