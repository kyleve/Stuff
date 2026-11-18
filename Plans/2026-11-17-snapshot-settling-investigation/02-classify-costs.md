# 02 — Classify measured costs

- Status: complete
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

Plan 01 is complete at `f60c1c974`, published in PR #524. The four focused controls and isolated CI trace are complete. Retain unsuccessful runs with their errors; never substitute a favorable run without describing the failure.
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

Ranked candidate experiments, supported by the overhead and CI evidence below; cost rows overlap and are not savings estimates:

| Candidate | Measured scope | Required next evidence |
| --- | --- | --- |
| Remove unnecessary measurement settling | 308 duplicate-stage captures; 95.652s local / 118.493s CI probe settling | Classify synchronous sizing versus async height changes. Verify early/normal/later geometry and content, retaining the late-changing measurement cases as adversaries. |
| Reduce render work or sample less often | 337.658s local / 465.656s CI inside render calls across stages | Profile a bounded native/static pair to identify render work versus synchronization. Separate fewer samples from faster completion; an unchanged floor can preserve wall duration. |
| Use specific completion signals or lower eligible floors | Content settling 325.181s; 835 early-stable calls across stages | Run proposed completion in observation-only mode. Include all seven late-change examples plus delayed work, native chrome, retry, and accessibility guards. |
| Avoid repeated settling after geometry/actions | Native insets, post-action, and accessibility preparation total 39.679s local / 49.430s CI | Establish which operation invalidates prior readiness; verify scrolling, native insets, and annotation geometry before reusing evidence. |

Focused controls selected from the trace: `WhereUISnapshotTests/FlightReviewPointRowSnapshotTests` (20 sampled calls, all unchanged, including measurement) and `WhereUISnapshotTests/MainTabsSnapshotTests` (66 sampled calls, including native/async work and a late change). Run both families together in each of four serial invocations, alternating off/on twice, with identical `--review --record never` flags and unchanged built products.

The first control invocation used the scheme name `StuffSnapshotTests` as the bundle selector. Xcode exited 70 with zero tests. That invocation is retained under `snapshot-settle-investigation-results/controls`; it is not a timing sample. The four valid controls use the bundle identifiers from `.circleci/snapshot-shards.json`, separate work directories, and `controls/paired` artifacts.

## Focused overhead result

All four valid invocations use built products from `f60c1c974`, `--no-build --no-generate --record never --review`, and both selected `--only` identifiers. They run serially in off/on/off/on order. Each executes the same three passing functions with no retries. Off logs contain no timing or trace rows. Both on runs reconcile 68 captures and 86 settled calls, matching the selected full-run capture inventory and policies. Off-mode capture inventories are not directly observed.

| Diagnostic mode | First test-work duration | Second test-work duration | Mean |
| --- | ---: | ---: | ---: |
| Off | 79.353501s | 79.276533s | 79.315017s |
| On | 79.995873s | 79.576650s | 79.786262s |

The observed difference is +0.471244s (+0.594143%). Exact xcresult test-body durations exclude architecture checks, builds, and launch overhead. Two runs per mode in two families do not establish a suite-wide statistical bound or isolate the new trace from existing timing diagnostics. This small observed difference supports using the traces to rank broad costs; no optimization saving relies on an assumed zero-overhead correction.

Independent review verified the raw exports, diagnostic enablement, matching test selection, on-mode capture inventories, reconciliation, and arithmetic. Retained evidence: `controls/paired/runs.json`, `comparison.json`, the four raw logs/xcresult exports, and both on-mode trace directories.

## Isolated CI result

[CircleCI workflow 98afc1ac](https://app.circleci.com/workflow/98afc1ac-42ed-42ac-b732-9dce6f08629d) and [snapshot job 6e8676f2](https://app.circleci.com/workflow/98afc1ac-42ed-42ac-b732-9dce6f08629d/job/6e8676f2-b6ec-4fa1-96af-fa97190f0c4f) tested `f60c1c974596039cb640c726f6ce1607c1633f11`. Every worker's environment records that revision and Xcode 27.2 (27B52) on an Apple M4 Pro VM with six logical CPUs. Workers 0–3 pass; worker 4 explicitly has zero assigned suites and halts as intended.

All 935 captures and 78 test identities match local coverage and geometry. All 1,828 calls and 4,812 passes reconcile, with no retries or contradictory stability/floor flags. The only policy difference is the existing CI 2× maximum-deadline multiplier; minimum durations and the 120ms quiet window match.

| CI operation inside settling | Wall seconds | Share |
| --- | ---: | ---: |
| Render call | 465.656 | 79.8% |
| Suspension | 100.717 | 17.3% |
| Layout | 5.889 | 1.0% |
| Pixel normalization/comparison | 1.810 | 0.3% |
| Other | 9.404 | 1.6% |
| Total | 583.476 | 100% |

CI reasons: content 410.690s, measurement 123.356s, post-action 22.949s, native insets 15.023s, and accessibility preparation 11.458s. The same 308 sampled measurement calls cost 118.493s and precede sampled content settling. Median/p95/maximum render time is 79.896/214.959/775.466ms. There are fewer passes than locally but more rendering wall time. Only 390 sampled calls become stable before their floor, versus 835 locally. This strengthens the case for investigating render/proof cost instead of treating floors as the only opportunity.

Of 1,265 sampled CI calls, 1,219 show no pixel change. Two RootView measurement calls become stable and later change, corroborating the local counterexamples. Early low-resolution stability is insufficient as a general completion signal.

Per-worker test phases are 298.624, 326.137, 309.081, and 319.882s. These run on separate VMs; summed operation time is not workflow wall time and is not combined with local durations. No before/after saving is claimed.

Real staging, upload, download, and recomputation are verified. Retained `ci/` evidence includes original JSONL and summaries, JUnit, source/environment/assignment output, job/workflow metadata, artifact manifest, `verification.json`, `policy-check.json`, and the combined report. Successful CI does not upload full Xcode logs or xcresult bundles. Recomputed summaries agree within 3.13e-13s floating-point roundoff, with exact integer and identity counts. The root independently revalidated all raw trace records and capture inventories after collection.

## Outcome and next action

R-02 is satisfied. Q-03 and Q-05 are resolved with the limits above; no result requires an assumed zero-overhead correction. Findings and the completed step are published in [PR #524](https://github.com/kyleve/Stuff/pull/524). Source and runtime behavior remain at `f60c1c974`; the subsequent checkpoint changes only these plans.

Advance to plan 03 refinement. Start with explicit measurement eligibility and a separate focused investigation of render work/sampling. Keep case-owned completion hooks and repeated native/action stages in the selected scope. Deprioritize pixel-comparison micro-optimization: it accounts for only 0.3–0.4% of traced settling here. Preserve all seven local late-change cases and the CI RootView examples in the experiment's adversarial set.
