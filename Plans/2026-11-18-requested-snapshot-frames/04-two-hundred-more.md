# 04 — Compare 200 additional snapshots

Status: complete. Delivered in [PR 540](https://github.com/kyleve/Stuff/pull/540). Depends on the capture and comparison controls in [03](03-broader-single-mount.md). [Overview](README.md) · [STU-121](https://linear.app/kve/issue/STU-121)

## Question and coverage

The user requested 200 more images and accepts small changes caused by capture timing. Test 200 distinct existing reference files outside the earlier 92. Freeze the paths before measuring. Count one file per reviewed image, including a multi-panel sheet. Record the panel workload separately.

The [manifest](mount-200.txt) contains 172 individual references, 26 intrinsic cutsheets and two full-content cutsheets across 29 test methods. It spans WhereUI, InstallerKitUI, Flyover, Inspector and PeriscopeTools. It selects production test methods, fixtures, traits and reference groups. Include full-content views, intrinsic sheets, full-content sheets and two-axis content. Annotations and fixed viewports do not exercise this transfer of a measurement host to final capture.

## Method and acceptance

Use the normal test-suite entry points, on one pinned simulator, with recording disabled. The production renderer can already grow, tile, and capture full screens, apply traits and insets, execute hooks and assemble cutsheets. For the candidate, keep that renderer's measurement wrapper attached until the final draw. The simplified component prototype in Plan 03 lacks these screen and sheet behaviors.

Run three arms in fresh test processes, first in forward order, then in reverse order:

| Arm | Hosting and readiness |
| --- | --- |
| Baseline | Production measurement wrapper, then a separate capture wrapper. All declared waits. |
| Retained | Same measurement wrapper stays attached through capture. All declared waits. |
| Early | Same retained wrapper. Replace an ordinary final content settle with immediate layout when no preparation or pre-capture action is present. Preserve measurement readiness, explicit minimums, scroll/inset reconciliation and post-action waits. |

```swift
let mounted = try await measure(fixture, declaredReadiness)
let subject = trial.retainsMeasurementHost ? mounted : remountForCapture(mounted)
try await prepareAndSettle(subject, finalPolicy: trial.finalPolicy(for: fixture))
let actual = try drawAndEncode(subject)
compare(actual, reviewedReference)
```

Verify 200 unique outputs per arm/pass and actual mounted wrapper counts from tracing. Record capture/composition time separately from comparison and export. Apply the ordinary image verdict including panel membership, per-panel checks and sheet layout. Compare encoded data, decoded premultiplied RGBA, dimensions and run-to-run drift. Inspect material or unexpected differences visually. The ordinary comparator and a small number of changed pixels are individual pieces of evidence; a missing row, blank panel, changed geometry, or clipped content needs direct investigation. Reproduce a failure where helpful. Report the time and the observed trade-off for each arm, preserving reviewed references and normal capture defaults.

Root owns the simulator, comparisons and publication. The fixture investigator freezes the manifest and verifies outputs. The renderer and assertion investigators own their respective paths in the shared *test* library. An independent reviewer checks the complete diff and actual artifacts. Resolve Q-05 with measured evidence in this plan.

## Reproduce and inspect

Run `Plans/2026-11-18-requested-snapshot-frames/run-200` from the repository root. It invokes `./test --timings --record never` on the 29 owning test methods. The five bundles run on the same simulator. Each arm starts a new test process and uses the same test build. The first pass runs baseline, retained and early. The second runs early, retained and baseline.

Read `summary-200.json` in the printed output directory. Each reference has the ordinary comparator verdict, dimensions, timing phases for each actual native capture, and decoded-pixel comparisons against its reviewed PNG, the other arms and its repeat. The `images` directory under each arm mirrors the repository paths. The 28 comparison sheets each contain two panels, for 228 native captures per arm. The audit joins every panel to its own trace, checks the completed arm order and requires two wrapper attachments on the baseline and one on each candidate.

The inventory and renderer investigators reviewed Plan 04 against the previous 92 identities, source providers, two-axis support, hook ordering, trace identifiers and panel metadata.

## Timings

All six runs passed on the same iPhone 17 simulator running iOS 27.2. Each executed 29 test methods, produced the same 200 references at the same dimensions and accounted for 228 native captures. The exposure was 154 eligible captures across 148 reference files. Among the other 74 captures, 53 had a preparation or pre-capture action with ordinary settling, 13 specified a 1.5-second minimum, and eight were already immediate.

| Capture and sheet composition | Forward | Reverse | Wrapper attachments per run | Settle samples, forward / reverse |
| --- | ---: | ---: | ---: | ---: |
| Production baseline | 144.22 s | 145.39 s | 456 | 1,447 / 1,446 |
| One mount, declared waits | 143.70 s | 143.40 s | 228 | 1,447 / 1,442 |
| One mount, eligible early draw | 100.20 s | 101.41 s | 228 | 821 / 820 |

The earlier draw saved **44 seconds in both orders (30.5% and 30.2%)**. Final settling fell from 79.4 / 80.0 to 35.0 / 35.3 seconds. Intrinsic measurement still took 32.4 / 33.0 seconds. The extra host attachment accounted for 0.6 seconds in each baseline. The production renderer still measured, tiled, drew and encoded the same subjects in every arm.

The 148 eligible reference files took 91.55 / 92.07 seconds on the baseline and 47.78 / 48.37 seconds with early capture, a 47.8% / 47.5% reduction. The other 52 files took 52.67 / 53.32 and 52.42 / 53.04 seconds respectively. Across all 28 sheets, capture and composition took 24.65 / 24.91 seconds on the baseline and 20.35 / 20.46 seconds with early capture.

The local test phase includes comparison, experiment exports and runner overhead. It took 182.5 / 183.6 seconds for the baseline and 139.9 / 141.3 seconds for early capture. Project generation and compilation were timed separately. These measurements cover the selected 200 files.

## What the pixels caught

All 1,200 outputs passed the ordinary comparator. The two production controls were pixel-identical to one another on all 200 files. Comparing early capture with the paired production control gave the same result in both orders:

| Images | Difference |
| ---: | --- |
| 195 | Identical decoded pixels, including alpha. |
| 2 Periscope Viewer images | The Logs/Hierarchy segmented control differed by at most 2/255 per channel. The same two controls also differed with the regular final wait on a retained mount. |
| 2 Calendar comparison sheets | Light and dark planned-stay year overviews differed by at most 1/255 per channel. The panels and their positions matched. |
| 1 Flyover list | The Widget preview was still loading. |

Even the production renderer differed from the checked-in references on 27 images, all within the repository's normal tolerance. Comparing each candidate against fresh production captures isolated the five differences above.

Both early-capture processes rendered the same 200 decoded images. One of those repeatable images is wrong. On the iPad Flyover list, the expected Widget preview shows an orange circle, “Today” and “California · 29 days”. Both early runs show a loading spinner in that spot. Just 11,985 of the 22.45 million pixels differ by more than eight channel levels from the first production capture, about 0.053%. The maximum difference is 235/255. The full image passes the ordinary perceptual comparison. At full resolution the missing card is clear.

The list creates its rows lazily. A preview displays a progress indicator until its asynchronous content loader sets the loaded view. The last Widget row can have its final size while its content is loading. The canvas fixtures already wait for their visible previews and specify a 1.5-second material settle. The list does not publish the expected preview set used by that canvas readiness check. Keep its final settle until the list has a readiness check for the actual previews at capture size. [List layout](../../Shared/Flyover/Sources/FlyoverListView.swift) · [Preview loader](../../Shared/Flyover/Sources/FlyoverScreenContent.swift) · [Fixture](../../Shared/Flyover/SnapshotTests/FlyoverSnapshotTests.swift)

## Decision

Of the 148 files that exercised the shorter wait, 143 were pixel-exact to both live production controls and four showed only the small changes above. These 147 are candidates for a fixture-level opt-in. Using their measured early times and the current production times for the other 53 yields an estimated **43.5 seconds saved per pass**, about 30% of the 200-image baseline. This is a projection from the six measured runs. For a rollout requiring exact pixels, the 143 eligible exact matches alone account for an estimated 40.7–41.0 seconds of savings with production capture for the rest.

The cumulative experiment covers 292 distinct references out of the 877 on this branch. The 200-image trial contains ordinary full-content views and sheets, including accessibility text sizes. Native accessibility annotations and fixed-viewport captures require separate evidence.

## Verification

The independent implementation review covered the stack base `e479fa140`, the previously verified prototype at `b42bf4434`, the new capture paths, and the raw results in both orders. All 1,368 native traces had distinct identifiers. Review added a completed-run order check. Substituting a trace identifier, changing an early flag, or changing a retained capture to report two attachments in both evidence files each failed the audit. The earlier Banner and Locations audit produced its original report byte for byte with the updated host pixel reader.

With the experiment disabled, the full `SnapshotKitTestingTests` bundle passed 165 tests, including the existing seven expected issues exercised by the assertion and retry tests. The ordinary InstallerKit failure-card and WhereUI region-card snapshot methods also passed with 63 native captures, including accessibility and comparison paths.

With early capture enabled, the 23 focused tests across `PreMeasureHookTests`, `CapturePreparationTests` and `LargeViewCaptureTests` passed. They exercise wrapper identity and teardown, cancellation, preparation, two-axis tiling, scrolling and accessibility. SwiftFormat, Ruff, the first run's architecture checks and `git diff --check` passed.
