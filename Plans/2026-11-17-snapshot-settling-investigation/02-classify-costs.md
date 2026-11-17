# 02 — Classify measured costs

- Status: ready
- Depends on: [01](01-settle-tracing.md).
- Shared context: [Overview](README.md).

## Deliverable

Resolve Q-03 and Q-05 for R-02: a ranked, reproducible account of settling costs and specific candidate experiments.
The unknown result does not block this observational experiment.

## Experiment design

- Run one full local image suite with traces after regression checks. Keep capture geometry, flags, source revision, toolchain, host, retries, and case inventory in the evidence.
- Select two focused families from that trace, including ordinary/static sizing and native/async content. Run alternating on/off controls twice per mode, serially, using the same built products and `--record never`.
- The switch enables both existing capture timings and new traces. Report this as combined diagnostic overhead, not an isolated estimate of trace overhead. Compare precise test-body durations from xcresult; build and launch time are outside that comparison.
- Retrieve an isolated CI snapshot run of the instrumentation revision. Compare costs and classifications; do not combine local and CI absolute durations into one estimate.
- Bound the initial pass to one local full trace, four focused invocations, and one complete CI sample. Repeat only for a demonstrated instrumentation failure or unresolved measurement concern.
- Use selected system traces only when operation timings leave a material cause unexplained. Do not promise that elapsed sleep distinguishes app work from scheduler delay.
- Preserve raw artifacts outside Git; keep concise measurements, source/commands, and interpretation in this plan.

## Analysis and acceptance

Classify each reason/family by observed changes, time spent rendering/checking, minimum-duration gating, stability-proof gating, and repeated calls.
A phase can have multiple active gates. Do not sum overlapping conditions or call every sleep removable.
Record distributions and expensive outliers rather than only means.
Compare capture identities, dimensions, outcomes, and reference diagnostics against the current baseline.
An inconclusive overhead comparison may complete this experiment only if noise/overhead limits are explicit and no optimization relies on the uncertain estimate.
CI evidence can remain pending at an intermediate publication; do not mark this plan complete until obtained or an explicit scope revision documents its replacement.

The deliverable is a ranked candidate table with affected stages, measured cost, proposed mechanism, correctness evidence needed, and the next bounded experiment.
A negative finding is valid. Update the overview questions and refine [03](03-controlled-experiments.md) from the actual results.

## Recovery and resume point

Wait for plan 01's validated instrumentation. Retain unsuccessful runs with their errors; never substitute a favorable run without describing the failure.
No new Swift architecture is proposed: this plan consumes the trace schema and analysis tool from plan 01.

## Inputs from plan 01 validation

The full local trace on an Apple M5 Pro, Xcode 27.2 (27B52), and iPhone 17 / iOS 27.2 contains 935 captures, 1,828 settling calls, and 6,066 passes. All captures pass without retries. The capture inventory, pixel/tile geometry, and policies match the baseline. Six simulators were booted on the shared Mac; a process check found no other active Xcode test workload. This is not an isolated CI measurement.

| Operation inside settling | Wall seconds | Share of traced settling |
| --- | ---: | ---: |
| Low-resolution render call | 337.658 | 72.9% |
| Suspension, including scheduling and possible app work | 113.659 | 24.5% |
| Layout | 3.905 | 0.8% |
| Pixel normalization/comparison | 1.626 | 0.4% |
| Other, including skipped-call work | 6.554 | 1.4% |
| Total | 463.403 | 100% |

These are wall intervals, not sampled CPU attribution. Render cost can include synchronization inside the UIKit call. The median render takes 49.665ms, p95 107.649ms, and maximum 221.616ms. The 16ms sleep request is therefore not the actual sample cadence.

By reason: content 325.181s, measurement 98.544s, post-action 17.163s, native insets 13.489s, and accessibility preparation 9.026s. No scroll-reset call occurs in this full image run. Of 808 measurement calls, 500 skip and 308 settle; those 308 cost 95.652s and each has a subsequent sampled content settle.

Of 1,265 sampled calls, 1,224 never show a pixel change. In 835 calls the stability condition becomes true before the floor. Seven later change: MainTabs Adaptive-Year inner-portrait accessibility, PlanningRegionPicker Search dark measurement, four RootView measurements, and FlyoverCompact measurement. They disprove a general “return on the first stable window” rule for these fixtures. The other calls do not establish readiness beyond the final observation.

Provisional experiments, pending overhead and CI evidence; cost rows overlap and are not savings estimates:

| Candidate | Measured scope | Required next evidence |
| --- | --- | --- |
| Remove unnecessary measurement settling | 308 duplicate-stage captures; 95.652s of probe settling | Classify synchronous sizing versus async height changes. Verify early/normal/later geometry and content, retaining the late-changing measurement cases as adversaries. |
| Reduce render work or sample less often | 337.658s inside render calls across stages | Profile a bounded native/static pair to identify render work versus synchronization. Separate fewer samples from faster completion; an unchanged floor can preserve wall duration. |
| Use specific completion signals or lower eligible floors | Content settling 325.181s; 835 early-stable calls across stages | Run proposed completion in observation-only mode. Include all seven late-change examples plus delayed work, native chrome, retry, and accessibility guards. |
| Avoid repeated settling after geometry/actions | Native insets, post-action, and accessibility preparation total 39.679s | Establish which operation invalidates prior readiness; verify scrolling, native insets, and annotation geometry before reusing evidence. |

Focused controls selected from the trace: `FlightReviewPointRowSnapshotTests` (20 sampled calls, all unchanged, including measurement) and `MainTabsSnapshotTests` (66 sampled calls, including native/async work and a late change). Run both families together in each of four serial invocations, alternating off/on twice, with identical `--review --record never` flags and unchanged built products.
