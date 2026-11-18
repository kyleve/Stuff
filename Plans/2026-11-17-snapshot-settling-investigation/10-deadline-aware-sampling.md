# 10 — Schedule settling samples around decision times

- Status: executing
- Depends on: [07](07-overlap-snapshot-work.md), for the existing settling loop and observer.
- Integration prerequisite: [09](09-overlap-png-processing.md) establishes the accepted pipeline before performance trials. The isolated schedule prototype does not depend on PNG processing or the comparison cap.
- Shared context: [Overview](README.md), R-04, R-10, Q-13, X-02–X-04.
- Authorization: The user requested all proposed follow-ups on 2026-11-17.

## Intended outcome and evidence

Reduce redundant settling renders while retaining trustworthy completion. The phase-7 full local run spends 324.672s rendering settling samples; 1,809 samples have proof satisfied but the minimum duration unmet. These flags are not additive savings and do not prove that unobserved intermediate motion is harmless. The previously tested blanket 60ms interval did not improve elapsed time.

## Known requirements and exclusions

Preserve minimum durations, the fixed normalized anchor, one-unit per-channel tolerance with no area exemption, two matching passes spanning at least 120ms, maximum-duration semantics, cancellation, retry freshness, and the final sampled content. Do not replace pixel proof with a timer or discard changes observed before the floor. Respect MainActor suspension so app tasks can progress.

```mermaid
flowchart LR
    A[Existing sample and anchor observation] --> B[Proposed next-check schedule]
    B --> C[Cooperative suspension]
    C --> D[Existing layout, render, and pixel proof]
    D --> E{Existing proof and floor satisfied?}
    E -->|no| B
    E -->|yes| F[Capture]
```

The conservative candidate below invalidates the quiet proof across an intentionally extended wait. It compares the first resumed sample with the old anchor to retain observed changes, then establishes a new quiet window.

## Refinement trigger and acceptance

After plan 09 fixes the baseline, inspect raw pass traces and the current state machine. Define a bounded schedule with fake-clock/state-machine checks for transient motion, late changes, cumulative fades, missing samples, low cadence, timeouts, starvation, and cancellation. Test real hosted delayed content and native effects against fresh serial and delayed oracles. Use two interleaved focused pairs, then full local/isolated-CI validation for a qualifying candidate. Accept only repeatable elapsed savings, unchanged fidelity, and no extra retries; retain negative evidence and remove rejected schedules.

## Resume point

Author the reviewed floor-wait candidate in scratch while the active benchmark remains frozen. Integrate and run it after plan 09 establishes the performance baseline.


## Trace refinement — 2026-11-17

The full phase-7 trace separates the 1,809 proof-satisfied / floor-unmet samples by minimum duration:

| Minimum | Calls | Calls stable before minimum | Such samples | Render work in those samples |
| --- | ---: | ---: | ---: | ---: |
| 250ms | 1,083 | 700 | 920 | 35.526s |
| 500ms | 39 | 25 | 72 | 4.895s |
| 1s | 40 | 40 | 482 | 22.166s |
| 1.5s | 31 | 31 | 335 | 26.887s |

Only 70 calls have enough remaining minimum time, after first proof, to wait and establish an entirely new 120ms proof plus three estimated sample passes. A conservative reset-after-gap candidate therefore targets mostly raised floors. Ordinary 250ms calls instead offer a possible completion-alignment opportunity: avoid a render that finishes just before the floor and forces another pass. Neither estimate proves that skipping samples is safe or yields elapsed savings.

Potential schedules must bound unobserved gaps, retain the fixed anchor and observed-change flag, sample late changes before accepting, and never extend sleeps past a relevant failure deadline. A predicted render duration can schedule work but cannot establish completion; actual post-render time still owns the verdict. These are requirements for refinement, not a chosen schedule.

## Proposed bounded experiment

Test one conservative schedule first. Only pixel-deciding calls with an already completed quiet proof and a substantially unmet floor qualify. After the current sample, estimate the remaining proof work as 120ms plus three recent pass durations and the ordinary 16ms suspension. If the floor leaves more than this work, suspend until that work should begin, capped at one second and the next applicable failure deadline. Otherwise preserve the 16ms cadence. Quiescence-only mode stays unchanged.

An extended suspension discards the old matching-pass count and anchor timestamp. Keep the old normalized sample until the first resumed observation, so a net change still sets `observedChange`; then start a fresh anchor and require the original two matches over 120ms. A missing resumed sample breaks proof as before. Keep any earlier observed change forever within that settling call. Do not repeatedly extend within the newly started proof. A later extension is possible only after a complete new proof and another sufficiently distant floor.

This deliberately targets the 70 long-floor calls identified above. It does not claim that all 1,809 floor-blocked samples are removable. The alternative of keeping a completed proof through a long gap would offer broader savings, but adds a stale-proof assumption this first candidate avoids.

```swift
// Proposed policy; actual samples and post-render time retain every verdict.
if pixelProofIsComplete, floorHasRoomForFreshProof {
    let delay = min(timeBeforeFreshProof, oneSecond, timeBeforeFailureDeadline)
    if delay > ordinaryDelay {
        pixelStability.requireFreshProofAfterGap()
        try await clock.sleep(for: delay)
    }
}
// Observe against the previous anchor for change detection, then restart proof.
// Never infer stability or meet a deadline from the predicted render cost.
```

The schedule is a pure internal function with explicit elapsed time, minimum, maximum, starvation cap, observed-change state, proof state, and recent pass duration. It must be independently testable without UIKit or a real clock. The actual loop retains cooperative suspension, synchronous sample pools, cancellation handling, and original timeout checks after its fresh observation. Timing records the requested delay accurately.

## Execution and acceptance

1. Once plan 09 establishes its outcome, freeze the accepted pipeline and add a temporary same-binary schedule switch. Implement the pure scheduler and fresh-proof state transition in the existing stability observer. Keep the existing anchor tolerance and all public policies.
2. Cover short/default floors, long floors, no proof, changes, missing/dimension-changing samples, cumulative fades, low cadence, deadline clamping, and past-budget static/starved behavior. A resumed sample can never settle immediately, even when it matches an old proof. A late change after resumption must restart the full quiet window. Preserve cancellation during the longer suspension.
3. Exercise actual hosted delayed updates, including a transient change wholly within a long wait and persistent late content. Both must receive a new complete proof after resumption. Reuse color, single-pixel, timeout, native-effect, restoration, and retry guards through `./test --no-generate --only SnapshotKitTestingTests`.
4. Use two interleaved 110-capture pairs, reverse the second pair, and retain source, PNGs, complete traces, exact test/body elapsed, sample counts, and host RSS. Compare final normalized pixels with the same strict one-unit investigation threshold. Keep all floors, references, and tolerances unchanged.
5. Select the candidate only if elapsed savings repeat beyond control variation, without added retries or resource regression. A qualifying candidate requires a fresh delayed oracle, full 935-capture pair, isolated CI correctness/resource checks, and independent review. Fewer renders alone do not qualify.
6. Remove the experiment switch/export and verify the final source if accepted. Otherwise restore the accepted pipeline and publish the negative or inconclusive result with its limits. Do not broaden the experiment into unchecked stale-proof reuse merely to obtain a gain.

The prototype may conclude negative or inconclusive. Root owns source and local runs; independent review owns correctness and evidence checking. No competing simulator work is permitted. The completed plan-09 baseline remains a prerequisite for integration and performance trials.

## Readiness review

2026-11-17, root review at `730152408`: the accepted settling observer and loop are unchanged by the cap and PNG experiments. Authoring an isolated prototype therefore depends on completed plan 07, while performance integration depends on plan 09. This revision preserves serial measurements and the selected baseline in every timed arm.

The bounded schedule has explicit trigger, proof-reset, observed-change, cancellation, deadline, and rejection rules. It never reduces floors or accepts a pre-gap proof. The original normalized anchor, tolerances, and post-render verdict remain authoritative. The reviewed experiment fits the user's requested scope; no product decision blocks source prototyping. Mermaid is syntax-inspected, not renderer-verified. Status advanced through ready to executing. No tracked runtime source has changed for this phase.

## Source prototype and review

The isolated prototype is in `/private/tmp/stuff-snapshot-followups/sampling-prototype-source`. It changes the existing observer/loop, adds a pure delay policy, and leaves tracked benchmark source untouched. It is not yet compiled or timed.

Independent source review found no incorrect observer or deadline transition, but identified a validation gap: the initial hosted tests could pass without enabling the candidate or resetting proof. The revised tests call an internal explicit-policy overload and observe requested sleeps and actual sample events. A transient changes and returns during a confirmed extended wait. Its first resumed sample must establish a new anchor, followed by two matches spanning 120ms. A persistent update occurs after resumption and must restart proof again. Cancellation waits for an actual extended suspension and permits no later sample. Observations are internal, optional, MainActor-owned, and print no synthetic profile records.

Independent follow-up review confirms that the revised source tests explicitly exercise the candidate and guard proof reset and cancellation. Before acceptance, build these guards and show that removing the loop's proof-reset call makes the hosted regression fail. Runtime and mutation evidence remain pending.


## Integrated execution

Plan 09 completes at `afe231667` with eager PNG/8M retained. The five-file reviewed schedule/observer/test prototype is applied to that baseline. Temporary export, serial-oracle, and delayed-capture controls use the previously reviewed experiment helpers; they are off unless explicitly requested. Both timing arms retain the same pipeline and export path. `sampling-baseline-source/` preserves the clean accepted source.

First compile and run the pure schedule and hosted floor-wait guards. Then remove only the loop's `requireFreshProofAfterGap()` call and confirm that the hosted regression fails for the intended assertion. Restore the exact source before the complete framework run. Freeze the passing source before two interleaved timing pairs. No other candidate is included.

The first build finds four test-only Swift Testing macro errors: a bare mutating `observe` call inside `#expect` is expanded through an immutable closure parameter. Evaluate those calls into local results before asserting. The failed build and original test file remain in `sampling-guards/` and `sampling-initial-compile-test.swift`; no runtime result is claimed for that attempt.

All eight focused functions pass after the test-only macro correction. The mutation then builds and fails the intended hosted function in both parameter cases: the resumed sample is matching/stable instead of a new anchor, with zero subsequent matches and zero quiet duration. Cancellation still passes. `sampling-mutation-result.json` records exit 65, the expected assertion cause, and identical original/restored source hashes. The correct source is restored before further tests.

Independent integrated-source review finds no blockers and verifies the actual eight-function log, deadline semantics, preserved motion history, explicit candidate tests, and disabled-by-default oracle controls. Freeze the corrected module at `sampling-timed-source/`, run every framework function with the candidate enabled, then execute control / deadline / deadline / control. Only the deadline schedule and its proof reset differ between timing arms.

The complete candidate-enabled framework run passes all 182 functions (`sampling-framework`, 92.429s test phase). Independent review confirms the mutation's exact build/test cause and original/restored/frozen hash equality. All live Swift files still match `sampling-timed-source/`. The four focused timing runs now proceed in the declared order, with eager PNG, the 8M cap, and no other simulator workload.


## Result: retain the existing cadence

Each of the four runs passes 110 captures / six functions with zero retries, identical source hashes, geometry, 558,607,431 pixels, 114 tiles, and 170 call policies. Controls take no extended waits. Each candidate takes four waits in raised-floor Main Tabs cases; each resumed sample is a fresh nonstable anchor. Serial and delayed-oracle controls are off in both arms.

| Mode | Test phase | Exact test bodies | Render work | Samples |
| --- | ---: | ---: | ---: | ---: |
| Control 1 | 108.115s | 94.949402s | 39.327893s | 573 |
| Deadline 1 | 108.117s | 92.720838s | 36.770425s | 548 |
| Deadline 2 | 109.278s | 93.948913s | 36.907227s | 544 |
| Control 2 | 106.181s | 92.869889s | 38.011197s | 561 |

The candidate removes 25 and 17 samples. Mean render work falls 1.830719s (4.73%), but the test-body benefit reverses: 2.228564s faster in the first pair, 1.079024s slower in the second. Control body variation is 2.079513s. Test-phase time is unchanged in the first pair and 3.097s slower in the second; its mean rises 1.5495s (1.45%). The repeated-benefit gate fails. Fewer renders do not establish an elapsed improvement, so retain the ordinary 16ms cadence and remove the prototype.

Sampled peak host RSS rises only 0.09375MiB against the larger control. All strict comparisons preserve dimensions. The first pair's single two-unit Adaptive Locations pixel matches the known independent delayed serial PNG variants; the other pair and control/control stay within one unit. No references, floors, quiet windows, or tolerances change.

The selected cohort exercises four extended-wait calls per run, all with one-second floors. This result applies to the bounded candidate and selection; it does not measure a full-suite benefit or rule out every future scheduler. Full-suite, fresh-oracle, and CI adoption trials are not selected because the focused elapsed gate fails. `schedule-trace-verification.json` and `schedule-active-call-summary.json` retain actual activation, fresh-proof events, policies, and changed-call accounting.

Restore the exact `afe231667` module source and remove all schedule/oracle/export controls and added tests. Source identity checks now match `sampling-baseline-source/` for every Swift file. Regeneration, focused cleanup checks, independent evidence/cleanup review, artifact retention, and publication remain before completion.

Changed-call accounting sharpens the result: the four affected calls save 1.113875s / 1.027209s of rendering but only 0.122927s / 0.032821s of elapsed time. Their unchanged one-second floors still govern completion. This is observed local accounting, not a full-suite estimate.

Cleanup passes generation, 27 existing stability/rendering/timeout/trace functions (16.341s test phase), and whitespace checks. Independent review reconciles all raw timing, policy, pixel, memory, and mutation evidence; confirms all 70 restored Swift files and removed prototype files; and reports no blockers. Preserve the archive hashes and publish the rejected-adoption result before closing the checkpoint.

The final sampling archive contains 677 hash-verified files under `snapshot-followup-results/sampling/`. A separate 10-file `trace-transport/` archive preserves the collector reproductions and mutation evidence. The net Swift source/test diff against parent PR #528 (`6d55f21e5`) is empty. Publish this result; only the final lifecycle checkpoint remains.
