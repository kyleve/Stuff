# 07 — Investigate overlapping snapshot work

- Status: ready
- Depends on: [05](05-metal-and-sampling-experiments.md) and [06](06-deliver-sampling-improvements.md), for the accepted sampling baseline and measured costs.
- Shared context: [Overview](README.md), R-07, Q-10, X-02–X-04.
- Request: On 2026-11-17 the user proposed doing useful work for another snapshot while the current snapshot settles, then explicitly requested execution: “Let’s move onto phase 7!” This authorizes the bounded investigation and implementation of a validated result; it does not establish a safe parallel-capture architecture.

## Intended outcome

Measure whether overlapping work shortens elapsed snapshot execution while preserving exact capture identity, geometry, content readiness, retries, cleanup, and deterministic reporting. A supported negative result is valid. Do not promise savings equal to the recorded sleep duration.

## Starting constraints

The accepted local baseline records 108.067s of settle suspension across the full suite. This interval includes SwiftUI tasks, native commits, fixture progress, and scheduling delay. It is not a measurement of unused CPU time. UIKit layout and rendering remain MainActor work; moving their scheduling does not make them execute in parallel on that actor.

`SnapshotCaptureLock.withHost` currently owns the marked host window, animation state, and safe-area override globals across suspension. Its FIFO makes concurrent callers execute safely in sequence. `ConcurrentCaptureTests` specifically guards different inset overrides and restoration. Other capture paths detach and resize the shared window, retain its scene for native chrome, reparent accessibility subjects, and restore state on every exit. Releasing the lock around `Task.sleep` would violate these ownership rules.

Read the [previous concurrency experiments](../../Shared/SnapshotKitTesting/Guidance/experiments.md) before refinement. Uncontrolled in-process overlap previously caused more than 24 incorrect comparisons; multiple simulators sharing a render server were slower and failed captures. Those results rule out merely enabling parallel tests. They do not measure a new bounded pipeline with explicit ownership.

## Candidate boundaries

1. **Preparation overlap:** prepare one following fixture's independent data while the current capture remains the sole host owner. Preserve lazy construction, per-case model isolation, cancellation, and case-owned readiness hooks. Do not mount the next controller or mutate window, scene, traits, safe areas, or process animation state during preparation. Shared caches and reused worlds need an explicit reentrancy audit.
2. **Completed-image overlap:** compare or process one prior capture's immutable PNG while the next view settles. The existing capture lock is released before reference comparison, but comparison currently runs on the MainActor. Separate work that needs UIKit or test-reporting context from image-data computation before moving it. Preserve panel-level verdicts, reference normalization, ordered issues/attachments, and record-mode semantics. The observed 100.057s comparison phase includes decoding and review diagnostics; its whole duration is not a savings estimate or a proposed background task boundary.
3. **Hosted overlap:** investigate at most two independently owned host slots, with a coordinator serializing each render and every shared-state operation. First prove that both subjects can keep progressing while their window, scene, traits, native chrome, accessibility, and restoration state remain isolated. A second UIWindow alone is not that proof. Keep the existing serial path for unsupported content.

These are alternatives for investigation, not approved public APIs. Preparation and completed-image overlap may be useful even if hosted overlap fails. Keep at most two cases' work in flight initially. Do not alter floors, quiet proof, tolerance, coverage, or fixture content to make an overlap result pass.

```mermaid
flowchart LR
    A[Capture A owns hosted state] --> S[A suspends for readiness or settling]
    S --> P[Candidate: prepare independent data for B]
    S --> R[Resume A layout and pixel proof]
    P --> Q[B waits for safe hosting boundary]
    R --> F[A captures and restores state]
    F --> Q
    Q --> B[B becomes the host owner]
```

This sketch shows the lower-risk preparation candidate. A hosted-overlap design must add explicit ownership and cleanup diagrams before readiness.

```swift
// Proposed bounded preparation; names are sketches, not existing APIs.
async let nextData = prepareIndependentFixture(nextCase)
let current = try await existingSerialCapture(currentCase)
let prepared = try await nextData
try await existingSerialCapture(nextCase, preparedData: prepared)
```

The sketch omits cancellation/error delivery, ordered reporting, completed-image overlap, and how optional preparation is declared. Those are required refinement decisions, not implementation latitude.

## Refinement trigger and required evidence

After plans 05–06 settle the baseline, correlate waits with main-thread CPU and runnable fixture/UI work. Identify preparation that can actually move earlier, rather than counting all sleeps as available capacity. Read the relevant fixture owner contracts and historical concurrency fixes.

Before marking ready, define a bounded prototype, explicit eligible content, two-slot resource budget, cancellation and error paths, deterministic ordering, fairness, and fallback. Decide how timestamps and per-capture traces preserve real wall time under overlap: summed capture durations cannot establish a throughput gain. Supply capture-owned suite/test attribution before interleaving output; the current settling analyzer infers suite labels from serial log order, so unchanged reporting would misattribute concurrent work.

Require independent fresh-host serial/control/later oracles, interleaved trait and inset cases, late updates, cancellation of either slot, failed hooks, retry freshness, scene/animation restoration, accessibility, memory pressure, and no starvation of current-view work. Use `ConcurrentCaptureTests` as a minimum guard, not sufficient proof by itself. Positive local results require complete snapshot coverage and isolated CI comparison, including worker/job wall time and resource peaks. Do not run competing simulator workloads on the local Mac.

## Executable refinement — 2026-11-17

The first bounded experiment selects completed-image work within one provider invocation. Current source already returns immutable PNG data after restoring the host. Fixture builders and their mounted tasks remain lazy and serial. Preparation overlap offers no generic independent-data seam; hosted overlap requires redesign of the global-state owners. Audit those alternatives here, but do not combine their architectural changes with this first throughput experiment. A supported negative result completes this bounded experiment; untested alternatives remain explicit follow-ups in STU-121.

### Questions, method, and bounds

1. Decompose the existing comparison phase into review diagnostics and reference verification on the same 110-capture selection used in plan 05. Retain raw, capture-owned events with provider/test identity and monotonic timestamps. This observational run does not establish savings.
2. Prototype one background comparison of immutable image bytes while the main actor captures the next ordinary case. Preserve the FIFO capture lock. Use a structured task group with at most one comparison worker and one current capture. Drain the preceding result before submitting another worker, crossing a cutsheet boundary, or returning from the provider.
3. Only successful comparisons may bypass repeated pixel computation. The background result retains the exact reference bytes it checked; the existing serial `verifySnapshot` still owns file reads, record modes, attachments, and issues. Its strategy reuses success only when both PNG byte sequences still match the checked inputs. A mismatch, missing or malformed reference, changed file, or unsupported subject uses the existing serial comparator. Keep recording modes and cutsheets on the original path initially. Do not transfer UIKit views, controllers, timing objects, or attachments to the worker.
4. The worker constructs images and comparison state locally, uses an explicit scale instead of querying `UIScreen`, and returns Sendable values only. Check cancellation before and after each expensive synchronous operation. A synchronous library comparison may finish before cancellation returns; await it before scope exit. The parent starts no further capture or report after cancellation. Capture errors drain earlier completed work before reporting the later error, and retries retain the existing fresh-controller behavior.
5. Keep only one prior image payload and one current capture alive. Limit worker eligibility to ordinary captures of at most 8 million pixels; larger captures use the serial path. Measure process peak memory and reject an unbounded queue or a material resource regression. No global worker registry, detached task, or concurrency toggle ships from the prototype by default.

The initial pipeline stays inside a single serial test/provider, and its structured scope ends before the next test starts. Existing UUID capture identities still join settle events to timing rows. Unlike cross-test overlap, this does not invalidate the analyzer's current suite attribution. Prototype events also carry their own test identity and absolute monotonic timestamps. If implementation expands to multiple tests, add capture-owned test/suite attribution to the production trace and analyzer first. Measure actual test/process elapsed time; summed capture latency is not throughput under overlap.

```mermaid
flowchart LR
    A[Main actor captures A and restores host] --> PA[Worker compares immutable A bytes]
    A --> B[Main actor captures B under existing lock]
    PA --> J[Join A result]
    B --> J
    J --> V[Main actor verifies and reports A]
    V --> PB[Worker compares immutable B bytes]
    V --> C[Main actor captures C]
```

```swift
// Proposed bounded structure; reporting and recovery stay on MainActor.
await withTaskGroup(of: PreparedComparison.self) { workers in
    var pending: CapturedAssertion?
    for job in jobs {
        let current = await captureAsResult(job) // sole host owner
        if let pending {
            let prepared = await workers.next()
            finishInOrder(pending, prepared) // verify checked reference bytes again
        }
        guard !Task.isCancelled else { return }
        switch current {
        case let .success(capture):
            pending = capture
            workers.addTask { await prepareComparison(capture.png, capture.reference) }
        case let .failure(error):
            pending = nil
            report(error)
        }
    }
    await finishLastPendingAssertion()
}
```

The implementation must pass only copied Sendable input values to `addTask`, not the actor-owned capture shown for brevity. Unsupported subjects drain first and run serially. Completed results are reported in original case/configuration order, including reference failures.

### Verification and decision

- Preserve source copies and run manifests in `/private/tmp/stuff-snapshot-overlap`, then retain reviewed evidence in the session artifact directory. Record commands, environment switches, source hashes, simulator/runtime, test identities, image dimensions, retries, worker occupancy, and worker/main-actor execution intervals.
- Use `./test --no-generate --only SnapshotKitTestingTests` for affected framework contracts. Add focused guards for actual overlap, bounded backpressure, cancellation/drain, ordered errors, stale-reference fallback, malformed/missing reference behavior, and successful-versus-failing comparison equivalence. Reuse existing inset/trait, native scene, late-content, hook-error, retry, accessibility, and recording guards. Their serial capture remains unchanged.
- Use the five selected suites from plan 05 with `./test --snapshots --no-generate --record never --review --timings`, preserving the 110 capture identities. After a correctness pilot, run two interleaved serial/candidate pairs in one built binary. Require consistent reductions in actual test elapsed time beyond control variation, unchanged PNG geometry/content, no extra retries, no extra settle failures, and acceptable peak memory. Do not claim that overlapped phase totals are additive savings.
- If timing fails, retain the negative evidence and remove the prototype. If it passes, run an independent delayed fresh-host oracle, the complete 935-capture serial/candidate comparison, and isolated CI validation before accepting a default. No new references, coverage reduction, floor changes, or tolerance changes are allowed. Investigate differences before proceeding.
- Keep serial fallback for unsupported shapes and record modes. Before publication, simplify accepted code, run applicable formatting/tool checks, obtain independent review, and publish a separate stack slice above PR #527. A negative result publishes documentation and retained artifact locations only.

### Research and design review

At parent `64e349f14`, `assertSnapshotReference` runs review diagnostics and `verifySnapshot` synchronously on MainActor. Ordinary captures supply PNG Data. Cutsheets first compare per-panel images and compose their canvas; they are excluded from this first pipeline. The pinned SnapshotTesting image comparator can read `UIScreen.main.scale` unless given a scale; its failure path also creates image attachments. Therefore the worker uses an explicit scale, returns only success/fallback and diagnostic values, and keeps authoritative reporting serial.

Apple documents [UIImage creation and use across threads](https://developer.apple.com/documentation/UIKit/UIImage). Swift documents [structured task-group lifetime](https://docs.swift.org/latest/documentation/swift/taskgroup/) and [explicit concurrent execution](https://developer.apple.com/videos/play/wwdc2025/245/). These support immutable image computation, not background UIKit hosting. No hosted UI leaves MainActor.

Root plan review on 2026-11-17 checked source ownership, failure paths, bounded memory, recording semantics, test attribution, and acceptance gates. Dependencies 05–06 are complete. The user authorized execution; no product decision blocks this bounded experiment. The alternatives remain measured/audited separately, and this experiment does not promise hosted overlap. Mermaid syntax is inspected, not renderer-verified. Independent implementation review remains required.

## Resume point

Ready for the comparison-cost pilot, followed by the bounded worker prototype. Existing runtime behavior remains unchanged at this checkpoint. Track through [STU-121](https://linear.app/kve/issue/STU-121).
