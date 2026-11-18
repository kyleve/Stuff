# Snapshot settling investigation

These records describe the original #524–525 stack. The [controlled experiments](03-controlled-experiments.md) and [verified fixture changes](04-validated-improvements.md) from #525 are included independently in [PR 535](https://github.com/kyleve/Stuff/pull/535). Earlier tracing and classification records are linked at the original revision.

## Planning checkpoint

- Updated: 2026-11-17; implementation published at `1ef9b92b7` on `perf/snapshot-render-settling`, stacked on PR #524.
- Operation: Create a durable plan and execute the investigation.
- Requested scope: The user approved tracing what happens during settling, then measuring ways to shorten, remove, or recognize completion earlier. The user explicitly requested planning and execution on 2026-11-17.
- Stage: All four plans are complete. The user authorized and renewed execution of the series.
- Completed: Tracing and local/CI classification; bounded renderer and readiness experiments; five accepted consumer changes; independent review; 163 framework functions and all 935 image captures locally; and isolated CI at the implementation revision.
- Pending: None within this selected series. STU-121 retains the unselected CI color-format/sampling experiments and readiness follow-ups.
- Next action: Review PR #525 above #524. Future optimization starts from the explicit remaining scope in STU-121; no merge is assumed.
- Delegation: `/root/review_settling_candidates` completed source and raw local-evidence review. `/root/watch_settle_ci` completed exact-head CI collection and reconciliation; the root independently verified the records. All implementation results are integrated.

## Outcome and scope

Explain the remaining settling cost and deliver improvements supported by measured readiness and unchanged rendered results.
The first deliverable adds opt-in diagnostics without changing the capture policy.
Later changes follow observed causes rather than assuming that every wait is removable.

Track this work in [STU-121](https://linear.app/kve/issue/STU-121).
The existing WebKit navigation investigation remains in [STU-122](https://linear.app/kve/issue/STU-122).

## Starting evidence

The full local profile before this investigation on Xcode/iOS 27.2 passes 935 captures and 78 functions without retries.
Its test phase takes 809.765s. That timing-only run omitted `--review`; it is not the comparable control for plan 04. Capture settling costs 352.494s; intrinsic measurement, including probe settling, costs 130.496s.
The run makes 6,010 settle passes. Existing totals merge several reasons for settling and do not separate sleep, layout, rendering, and pixel comparison.

The renderer can settle during measurement, initial capture, inset reconciliation, a post-capture action, scroll restoration, and accessibility preparation.
The pixel loop uses a fixed anchor, one-unit per-channel noise tolerance, two matches across 120ms, and a minimum duration.
The default floor is 250ms. Async work can run while the loop is suspended, so sleep duration is not automatically avoidable time.

[Previous experiments](../../Shared/SnapshotKitTesting/Guidance/experiments.md) rule out using global quiescence or a single UI update callback as general completion evidence for the current hosts.
The [earlier WebKit experiment](../2026-11-16-snapshot-measurement/01-webkit-readiness.md) already attributes most readiness time to navigation; repeating that decomposition is outside this first horizon.
Repository source and the pinned-runtime measurements suffice for this observational deliverable. New platform claims require current primary evidence before implementation.

## Review and delivery

- Plan review: All four plans have recorded reviews. Independent source, local raw-evidence, and CI reconciliation have no remaining blockers.
- Implementation: All plans are complete. PR #525 at `1ef9b92b7` passes local and isolated-CI checks; the final checkpoint changes documentation only.
- Publication: Plan commit `230c5048d` and instrumentation `f60c1c974` are in [PR #524](https://github.com/kyleve/Stuff/pull/524). Experiment groundwork `433450cba` and implementation `1ef9b92b7` are in [PR #525](https://github.com/kyleve/Stuff/pull/525). Both are linked from STU-121.

## User stories and requirements

| ID | Requirement | Story | Deliverable |
| --- | --- | --- | --- |
| US-01 | Maintainers need faster snapshot feedback with trustworthy content and geometry. | User request | Whole series |
| R-01 | Attribute every settling call and its work without changing its verdict. | US-01 | [01](https://github.com/kyleve/Stuff/blob/0c70aabfaffee08342c96deeec04d48b486fbe9a/Plans/2026-11-17-snapshot-settling-investigation/01-settle-tracing.md) |
| R-02 | Retain reproducible local and isolated-CI evidence, including instrumentation overhead and limits. | US-01 | [02](https://github.com/kyleve/Stuff/blob/0c70aabfaffee08342c96deeec04d48b486fbe9a/Plans/2026-11-17-snapshot-settling-investigation/02-classify-costs.md) |
| R-03 | Evaluate earlier completion and removed work against normal and later rendered results. | US-01 | [03](03-controlled-experiments.md) |
| R-04 | Deliver only validated improvements; preserve failures, cancellation, retry isolation, dimensions, references, and tolerances. | US-01 | [04](04-validated-improvements.md) |

## Exclusions

| ID | Boundary | Reason |
| --- | --- | --- |
| X-01 | Do not alter settling policy, quiet windows, floors, sampling cadence, or image comparisons in plan 01. | Instrumentation must establish the control. |
| X-02 | Do not reduce coverage, record references, or hide loading states. | The user requested faster execution of current coverage. |
| X-03 | Do not replace pixel proof with global quiescence or UI-update callbacks alone. | Prior pinned-runtime experiments found false completion or absent callbacks. |
| X-04 | Do not run competing simulators on one Mac. | Their render-server contention invalidates measurements. |

## Execution order and planning horizon

1. [01 — Trace settling](https://github.com/kyleve/Stuff/blob/0c70aabfaffee08342c96deeec04d48b486fbe9a/Plans/2026-11-17-snapshot-settling-investigation/01-settle-tracing.md): complete; observational implementation and regression checks.
2. [02 — Classify measured costs](https://github.com/kyleve/Stuff/blob/0c70aabfaffee08342c96deeec04d48b486fbe9a/Plans/2026-11-17-snapshot-settling-investigation/02-classify-costs.md): complete; full local trace, focused overhead controls, and isolated CI evidence.
3. [03 — Controlled experiments](03-controlled-experiments.md): complete; evidence and regression groundwork published in [PR #525](https://github.com/kyleve/Stuff/pull/525).
4. [04 — Validated improvements](04-validated-improvements.md): complete; explicit readiness and preparation for five providers, with full local/CI verification.

The user authorized this series and its execution. Later design choices remain provisional, not additional product requirements.
Advance the horizon after the measurements identify candidate paths and required correctness evidence.
The first PR contains the plan and observational groundwork; subsequent commits/PRs keep each verified change separate.

## Shared decisions

- 2026-11-17: Use the existing `--timings` opt-in. Capture-owned trace identities and call ordinals distinguish repeated stages and retry attempts without a global registry.
- 2026-11-17: Buffer pass records in memory and emit one diagnostic line on each settle exit. Never print or encode JSON inside the sampling loop.
- 2026-11-17: Report active operation times separately from overlapping floor/quiet-window conditions. Sleep duration includes opportunities for app work; it is not a savings estimate.
- 2026-11-17: Preserve the existing pixel observer's verdict and expose diagnostic events from the same observation. Do not independently re-render or compare for tracing.

## Questions and resolutions

| ID | Status | Question | Impact | Resolution or next action |
| --- | --- | --- | --- | --- |
| Q-01 | closed | May implementation start? | All plans | The user explicitly requested planning and execution. Integrated into the checkpoint and horizon. |
| Q-02 | closed | How should tracing be enabled and correlated? | R-01, plan 01 | Existing timing opt-in, capture-owned identity, and call ordinal. Integrated in plan 01 and reviewed against retry reuse. |
| Q-03 | closed | Which calls are floor-, proof-, rendering-, or content-change-dominated? | R-02/R-03 | Plan 02's verified local/CI traces rank measurement removal and render work/sampling first. Rendering occupies 72.9% locally and 79.8% on CI; floor/proof flags remain overlapping conditions. Deeper attribution inside the render call belongs to plan 03. |
| Q-04 | closed | Which earlier completion or removal is safe? | R-03/R-04 | Repeated normal/candidate runs and an independent delayed oracle match all 62 images for five providers. Accept their explicit immediate measurement and Onboarding preparation. Reject Settings on geometry failures and both renderer candidates on timing. Integrated in plans 03–04; remaining owner-task and native readiness work stays in STU-121. |
| Q-05 | closed | Does trace overhead materially affect the observed timing? | R-02 | Two runs per mode in a static/native pair show +0.471s (+0.594%) for combined diagnostics. Plan 02 records that this is neither a suite-wide bound nor an isolated trace-only estimate. Broad cost ranking uses the observed data; savings do not assume zero overhead. |

## Plan review

2026-11-17, base `cd293e851`: reviewed the full series for scope/dependencies and plans 01–02 for implementation detail.
The design preserves current verdict timestamps, pixel thresholds, cancellation, cleanup, and maximum-duration behavior.
Pass timings overlap deadline conditions; the analyzer must not sum those conditions into extra wall time.
Trace identities must survive failed attempts, and incomplete trace logs must not look like zero work.
No user decision blocks plans 01–02. Q-03–Q-05 are the experiments' questions, not missing prerequisites.
Mermaid syntax is inspected; no renderer verification is claimed. Pseudocode is not compilation evidence.

2026-11-17 execution review: `f60c1c974` passes local validation and all GitHub/CircleCI checks. Independent review verifies source semantics, identities, operation accounting, seven late-change examples, and the paired controls. CI collection plus independent root recomputation verify 935 captures and 78 test identities with unchanged geometry and policies apart from the existing CI timeout multiplier. The next milestone changes behavior only after plan 03 is refined and reviewed; current work establishes evidence rather than claiming a speedup.

2026-11-17 completion review: the selected 62 captures save 18.938s (34.69%) in repeated local controls. The complete local suite saves 17.882s of capture work (2.30%) with unchanged coverage; CI verifies the same changes but does not establish an overall wall-time improvement. Both renderer prototypes remain unshipped after local trials. Their CI behavior and altered sampling frequency are still open questions in STU-121. See plan 04 for complete evidence and limits.
