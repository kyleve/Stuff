# Snapshot settling investigation

## Planning checkpoint

- Updated: 2026-11-17; phase 7 implementation `689cef15c` is published in ready-for-review PR #528 on `perf/snapshot-overlap`, above PR #527 at `64e349f14`. Local acceptance, isolated CI validation, and independent review pass; the final checkpoint changes documentation only.
- Operation: Refine and execute phase 7 after the user's explicit request, “Let’s move onto phase 7!” Preserve completed plans 01–06.
- Requested scope: The user approved tracing what happens during settling, then measuring ways to shorten, remove, or recognize completion earlier. The user explicitly requested planning and execution on 2026-11-17.
- Stage: Plans 01–07 are complete. Plan 07 adopts bounded background image comparison for its repeatable local gain. Background saves 11.80% and MainActor interleaving saves 5.98% on the selected workload; neither adds a second host.
- Completed: Plans 01–04: tracing and local/CI classification, five accepted consumer changes, 163 framework functions, all 935 local captures, and isolated CI. Follow-up: Metal prerequisites, eight paired timing runs with 880 capture assertions, 23 focused framework functions, complete prototype cleanup, and independent review. No follow-up sampler change is accepted.
- Completed locally in phase 7: six focused timing runs, independent 110-capture delayed oracle, 173 framework functions plus 28 final focused functions, and a same-binary 935-capture pair. Full test time improves 851.900s → 810.041s (4.91%); capture identity and geometry stay unchanged. Independent review and lint pass.
- Completed CI: both revisions pass 935 captures / 78 functions with zero retries and matching geometry/policies. Candidate runtime `689cef15c` passes all CircleCI and manual GitHub gates. Summed worker test time falls 16.293s, but the longest test phase rises 15.059s and snapshot job wall rises 19.250s. No CI elapsed-time gain is established.
- Pending: No selected phase remains. STU-121 retains CI throughput uncertainty, independent fixture preparation, additional hosted slots, and other readiness questions.
- Validation exception: The user explicitly requested ignoring the known intermittent `StoreRemoteChangeSourceTests.historyObserverForwardsExternalAuthorForItsStore()` failure in the control unit job. Snapshot jobs and all other failures remain part of acceptance.
- Next action: Normal review and merge of the open stack; no merge is assumed or performed. Candidate CircleCI pipeline #2540 and GitHub run 44213751266 test implementation `689cef15c`. The final evidence checkpoint is documentation only, and STU-121 remains In Review.
- Delegation: `/root/review_settling_candidates` and `/root/watch_settle_ci` completed the original implementation review and CI reconciliation. `/root/review_metal_sampling` independently reviewed all follow-up artifacts, cleanup, and the overlap outline. The root independently recomputed that evidence. `/root/watch_settle_ci` completed the phase-7 CI and publication handoff. `/root/review_snapshot_overlap` independently reviewed phase-7 source, local evidence, and raw CI accounting; its timing-accounting and resource-bound findings are tracked in plan 07.

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
