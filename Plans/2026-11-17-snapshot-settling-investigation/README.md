# Snapshot settling investigation

## Planning checkpoint

- Updated: 2026-11-17, starting from PR #528 checkpoint `7ccd0383e`; its tested runtime is `689cef15c`.
- Operation: Revise and execute follow-up experiments after the user requested, “let’s do them all and see what helps.”
- Requested scope: Repeat the mixed CI comparison, evaluate a larger bounded comparison worker, move immutable PNG processing off the capture path, and test deadline-aware settling samples. Preserve completed plans 01–07.
- Stage: Plans 08, 08a, and 09 are complete. Plan 10 finishes its bounded trials: fewer renders do not yield repeatable elapsed savings. The accepted 16ms cadence, eager PNG, and 8M bound are restored for final checks and publication; the trace repair remains.
- Completed: Plans 01–07 and PR #528 are published. Local phase-7 savings are 41.859s / 4.91%. Its isolated CI pair preserves all captures but establishes no elapsed-time gain.
- Pending: [10](10-deadline-aware-sampling.md). Keep accepted changes only after timing, fidelity, cancellation, and resource gates.
- Validation exception: Continue to ignore the user-identified intermittent `StoreRemoteChangeSourceTests.historyObserverForwardsExternalAuthorForItsStore()` failure. Do not investigate or retry it. Other failures remain in scope.
- Branch: `perf/snapshot-followup-experiments`, stacked above PR #528. The user's untracked `.agents/skills/simple-english/` remains untouched.
- Next action: Complete the sampling cleanup checks, independent review, and evidence archive, then publish the final result and close the series checkpoint. Linear reporting awaits the explicit destination approval requested after automatic review rejected that update; repository work continues.
- Delegation: Root owns local prototypes, tests, plan integration, and publication. `/root/watch_settle_ci` owns only the explicitly assigned repeat-CI watch and raw evidence; it must not change repository files or publish. `/root/review_snapshot_followups` owns fresh read-only implementation/evidence review before publication.

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

- Plan review: Plans 01–04 have completed reviews. Plan 05 and its bounded color-format refinement are reviewed for execution. Plan 06 has a reviewed negative-result delivery procedure. Plan 07 now has a reviewed bounded experiment; preparation and multiple-host alternatives remain outside its first prototype.
- Implementation: Plans 01–04 are complete. PR #525 at `1ef9b92b7` passes local and isolated-CI checks; its final checkpoint changes documentation only. Follow-up plan and Metal findings are published in [PR #527](https://github.com/kyleve/Stuff/pull/527).
- Publication: Plan commit `230c5048d` and instrumentation `f60c1c974` are in [PR #524](https://github.com/kyleve/Stuff/pull/524). Experiment groundwork `433450cba` and implementation `1ef9b92b7` are in [PR #525](https://github.com/kyleve/Stuff/pull/525). Both are linked from STU-121.

## User stories and requirements

| ID | Requirement | Story | Deliverable |
| --- | --- | --- | --- |
| US-01 | Maintainers need faster snapshot feedback with trustworthy content and geometry. | User request | Whole series |
| R-01 | Attribute every settling call and its work without changing its verdict. | US-01 | [01](01-settle-tracing.md) |
| R-02 | Retain reproducible local and isolated-CI evidence, including instrumentation overhead and limits. | US-01 | [02](02-classify-costs.md) |
| R-03 | Evaluate earlier completion and removed work against normal and later rendered results. | US-01 | [03](03-controlled-experiments.md) |
| R-04 | Deliver only validated improvements; preserve failures, cancellation, retry isolation, dimensions, references, and tolerances. | US-01 | [04](04-validated-improvements.md) |
| R-05 | Determine whether fewer samples or Metal layer rendering reduce settling time without false completion. | US-01 | [05](05-metal-and-sampling-experiments.md) |
| R-06 | Deliver validated follow-up savings with explicit fallback where required; preserve the existing quiet proof and case floors. | US-01 | [06](06-deliver-sampling-improvements.md) |
| R-07 | Determine whether useful work can overlap settling without corrupting host state, delaying required UI work, or changing snapshots. | US-01 | [07](07-overlap-snapshot-work.md) |
| R-08 | Distinguish CI variation from throughput effects and evaluate larger bounded comparisons. | US-01 | [08](08-expand-bounded-comparison.md) |
| R-09 | Determine whether immutable PNG processing can overlap capture without changing normalized pixels or reporting. | US-01 | [09](09-overlap-png-processing.md) |
| R-10 | Reduce premature settling renders without weakening the anchor proof, floors, late-change detection, or failure policy. | US-01 | [10](10-deadline-aware-sampling.md) |

## Exclusions

| ID | Boundary | Reason |
| --- | --- | --- |
| X-01 | Do not alter settling policy, quiet windows, floors, sampling cadence, or image comparisons in plan 01. | Instrumentation must establish the control. |
| X-02 | Do not reduce coverage, record references, or hide loading states. | The user requested faster execution of current coverage. |
| X-03 | Do not replace pixel proof with global quiescence or UI-update callbacks alone. | Prior pinned-runtime experiments found false completion or absent callbacks. |
| X-04 | Do not run competing simulators on one Mac. | Their render-server contention invalidates measurements. |

## Execution order and planning horizon

1. [01 — Trace settling](01-settle-tracing.md): complete; observational implementation and regression checks.
2. [02 — Classify measured costs](02-classify-costs.md): complete; full local trace, focused overhead controls, and isolated CI evidence.
3. [03 — Controlled experiments](03-controlled-experiments.md): complete; evidence and regression groundwork published in [PR #525](https://github.com/kyleve/Stuff/pull/525).
4. [04 — Validated improvements](04-validated-improvements.md): complete; explicit readiness and preparation for five providers, with full local/CI verification.
5. [05 — Metal and sampling experiments](05-metal-and-sampling-experiments.md): complete; both Metal adapters and both sampling candidates are rejected for adoption.
6. [06 — Deliver the sampling result](06-deliver-sampling-improvements.md): complete; reviewed findings published and original Swift source restored.
7. [07 — Overlap snapshot work](07-overlap-snapshot-work.md): complete; bounded background comparison is published in PR #528 with local gains, full correctness/resource validation, and explicit mixed CI timing results.

8. [08 — Expand bounded comparison](08-expand-bounded-comparison.md): complete; retain 8M after local gains fail the final retry gate. Bounded CI repeats remain inconclusive.
   [08a — Preserve complete traces beside native logs](08a-trace-log-framing.md): complete; strict transport passes fresh full CI, while historical failed samples remain excluded.
9. [09 — Overlap PNG processing](09-overlap-png-processing.md): complete; retain eager normalization after the repeated-benefit gate is not met.
10. [10 — Deadline-aware sampling](10-deadline-aware-sampling.md): executing the conservative floor-wait prototype against eager PNG/8M.

The current horizon measures the reviewed sampling prototype against the accepted eager-PNG/8M baseline. A qualifying candidate needs full fidelity, resource, and CI validation; an inconclusive or negative result restores that baseline.
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
| Q-06 | closed | Can CARenderer sample hosted UIKit/SwiftUI content faithfully and faster, including late updates and native effects? | R-05/R-06 | Plan 05 rejects both tested adapters: the live layer detaches from UIKit, and the public snapshot-view route loses source content. No Metal backend is selected. This local result does not rule out every Metal design; CI GPU capability remains untested. |
| Q-07 | closed | Does a minimum sample interval avoid excessive render work without delaying completion or missing changes? | R-05/R-06 | Plan 05 rejects standalone 60ms scheduling after both pairs are slower. Extended-color samples plus 60ms reduce rendering 16.18% but leave capture work flat; the small end-to-end difference is within control variation. The existing cadence and format remain unchanged. |
| Q-08 | closed | Does an accepted local candidate improve isolated CI with its actual GPU availability? | R-06 | No candidate passes the local adoption gate, so no CI candidate trial is selected. Actual CI GPU availability and color-format performance remain unmeasured follow-ups in STU-121; the negative local result is not a CI claim. |
| Q-09 | closed | Would Metal image comparison materially reduce settling cost? | R-05 | Current local normalization and pixel checks total 1.626s, about 0.2% of capture work. Do not add a settling comparison kernel. Full reference comparison is a separate 100.057s phase in the review-enabled run, including PNG handling and diagnostics; its library already has a conditional Metal/MPS path. Profiling that path remains separate STU-121 scope. |
| Q-10 | closed | Can another snapshot's useful work run during settle suspensions safely and profitably? | R-07 | Plan 07 validates one immutable comparison worker alongside one serial hosted capture. Repeated focused runs and the full local pair improve elapsed time; isolated CI preserves correctness but does not establish an elapsed gain. MainActor interleaving is a smaller measured alternative. Preparation and additional hosted slots remain separate STU-121 follow-ups. |
| Q-11 | closed | Is phase-7 CI throughput repeatable, and can a larger bounded comparison improve it? | R-08 | Plan 08 completes within its bounded method: no new valid CI pair, and 12M fails the no-added-retry gate despite local gains. Retain 8M; reviewed and published at `edb688245`. |
| Q-12 | closed | Can PNG processing safely leave the capture critical path? | R-09 | Plan 09 passes ownership/cancellation/fidelity guards but misses the repeated-benefit gate at retained 8M. Keep eager normalization; reviewed result and cleanup are published at `afe231667`. |
| Q-13 | open | Can decision-time scheduling remove render work without missing late changes or delaying proof? | R-10 | Refine plan 10 with adversarial traces and independent delayed captures. |

## Follow-up research and review

The user authorized these follow-ups after discussing the color-conversion profile and Metal on 2026-11-17. At `1ef9b92b7`, local settling costs 447.534s, including 326.818s rendering and 1.626s pixel checks. GPU comparison alone therefore targets little measured work.

The pinned iOS Simulator 27.2 `CARenderer.h` exposes `init(mtlTexture:options:)`, output color space, and a client Metal queue. Apple's [CARenderer documentation](https://developer.apple.com/documentation/quartzcore/carenderer) establishes an offscreen layer renderer, not equivalence to UIKit's current-frame hierarchy capture. The header requires client synchronization when a queue is supplied; scheduling does not establish completion. Layer fidelity and actual CI acceleration remain experimental questions.

2026-11-17, base `75978860f`: reviewed plans 05–06 against the source and completed experiments. The bounded experiment can conclude negatively; it does not promise a GPU default. Keep final capture rendering unchanged, test independent hosts before a UIKit capture can flush the candidate, include GPU readback/setup in timing, and retain explicit negative evidence. Mermaid is inspected but not renderer-verified. No product decision blocks the experiment; Q-06–Q-08 describe its unknowns. Implementation and evidence require independent review before publication.

## Plan review

2026-11-17, base `cd293e851`: reviewed the full series for scope/dependencies and plans 01–02 for implementation detail.
The design preserves current verdict timestamps, pixel thresholds, cancellation, cleanup, and maximum-duration behavior.
Pass timings overlap deadline conditions; the analyzer must not sum those conditions into extra wall time.
Trace identities must survive failed attempts, and incomplete trace logs must not look like zero work.
No user decision blocks plans 01–02. Q-03–Q-05 are the experiments' questions, not missing prerequisites.
Mermaid syntax is inspected; no renderer verification is claimed. Pseudocode is not compilation evidence.

2026-11-17 execution review: `f60c1c974` passes local validation and all GitHub/CircleCI checks. Independent review verifies source semantics, identities, operation accounting, seven late-change examples, and the paired controls. CI collection plus independent root recomputation verify 935 captures and 78 test identities with unchanged geometry and policies apart from the existing CI timeout multiplier. The next milestone changes behavior only after plan 03 is refined and reviewed; current work establishes evidence rather than claiming a speedup.

2026-11-17 completion review: the selected 62 captures save 18.938s (34.69%) in repeated local controls. The complete local suite saves 17.882s of capture work (2.30%) with unchanged coverage; CI verifies the same changes but does not establish an overall wall-time improvement. Both renderer prototypes remain unshipped after local trials. Their CI behavior and altered sampling frequency are still open questions in STU-121. See plan 04 for complete evidence and limits.

2026-11-17 follow-up outline review: `/root/review_metal_sampling` verified plan 07 against the capture lock, MainActor comparison path, and concurrency regression tests. R-07/Q-10 map to the outline and dependencies remain acyclic. Preparation, completed-image work, and hosted overlap remain distinct candidates. Cancellation, reporting order, resource budgets, and host isolation require executable design before readiness. This review does not establish safe overlap or authorize bypassing the existing capture lock.

2026-11-17 follow-up completion: plans 05–06 are published in PR #527 at `1594ea543`. Independent and root recomputation agree on all eight timing runs and prototype cleanup. Neither local Metal adapter qualifies; the 60ms interval is slower, and combined extended-color/60ms samples reduce render time without a repeatable overall gain beyond control variation. The final Swift source matches the parent exactly. Plan 07 remains a separately requested outline, not an implemented overlap feature.

2026-11-17 phase-7 completion review: implementation `689cef15c` passes 173 framework functions, 28 final focused functions,
repeated focused trials, the independent delayed oracle, and the 935-capture local/CI gates. Independent raw-evidence review
reproduces identities, geometry, policies, retries, timing, and sampled resources. The full local pair saves 41.859s (4.91%).
The isolated CI pair has lower summed test work but a slower longest worker and job wall, so no CI elapsed gain is claimed.
The final checkpoint changes documentation only; STU-121 remains In Review with the remaining unselected investigations.


2026-11-17 follow-up plan review, base `7ccd0383e`: the user explicitly authorizes all three experiments and the CI repeat. Root checked plans 08–10 against the source and completed phase-7 evidence. Plan 08 preserves one worker, serial hosting, current reference policy, and recorded resource limits; the bounded experiment may conclude negative or inconclusive. Plans 09–10 retain explicit refinement triggers and do not prescribe an unverified immutable-image transfer or sample schedule. No product answer blocks plan 08. Mermaid is syntax-inspected, not renderer-verified. Implementation requires fresh independent review before publication.
