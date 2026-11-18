# 04 — Compare 200 additional snapshots

Status: executing. Depends on the capture and comparison controls in [03](03-broader-single-mount.md). [Overview](README.md) · [PR 540](https://github.com/kyleve/Stuff/pull/540) · [STU-121](https://linear.app/kve/issue/STU-121)

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

The inventory and renderer investigators reviewed Plan 04 against 200 distinct paths, the prior 92 identities, actual source providers, two-axis support, hook ordering, trace identifiers and panel-map semantics. The experiment is running on the simulator.
