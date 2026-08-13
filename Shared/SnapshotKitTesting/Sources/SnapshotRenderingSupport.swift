import SnapshotKit
import SwiftUI
import Testing
import UIKit

/// How a settle phase ended. Only ``settled`` and ``skipped`` mean the pixels
/// the capture is about to record are the ones the case declared — the rest
/// describe a capture the pipeline can't vouch for, so callers report them
/// instead of quietly proceeding.
@_spi(Testing) public enum SettleOutcome: Equatable {
    /// Renders reached pixel stability and held it through the quiet window.
    case settled
    /// The case declared `.immediate`, so no settle loop ran.
    case skipped
    /// The content was *observed* changing and was still changing when the
    /// budget elapsed. Whatever gets captured is an arbitrary frame of
    /// whatever is still in motion, which is how a flaky reference gets
    /// recorded.
    case timedOut(budget: TimeInterval)
    /// The loop never observed the content change, but render passes were too
    /// slow to *prove* stability (three matching samples) before the extended
    /// cap. A starved machine, not a moving view — or a view that renders no
    /// pixels at all (a zero-sized frame).
    case starved(passes: Int, cap: TimeInterval)
    /// The task was cancelled mid-settle.
    case cancelled
}

/// Fails the test when a settle phase ended somewhere the capture can't be
/// trusted from. A view still in motion at the budget records an arbitrary
/// frame, which is precisely how a flaky reference lands — the failure class
/// the settle loop exists to prevent — so it's louder than a log: a silent
/// timeout is indistinguishable from a clean capture in CI output.
@MainActor
func reportIfUnsettled(
    _ outcome: SettleOutcome,
    phase: String,
    of viewController: UIViewController,
    named name: String,
) {
    switch outcome {
        case .settled, .skipped:
            return
        case let .timedOut(budget):
            Issue.record(
                """
                Snapshot content never settled: the \(phase) phase for "\(name)" \
                (\(type(of: viewController))) was observed still changing \(budget.formatted())s \
                after hosting, so this capture is an arbitrary frame of whatever is still moving. \
                Freeze the motion at a deterministic phase behind `\\.isCapturingSnapshot` (the \
                Where app does this with `MotionIsStatic`), or — if the content is merely slow \
                rather than endless — raise the floor with `.settledAtLeast(minDuration:)`.
                """,
            )
        case let .starved(passes, cap):
            Issue.record(
                """
                Snapshot settle starved: the \(phase) phase for "\(name)" \
                (\(type(of: viewController))) completed only \(passes) render pass(es) in \
                \(cap.formatted())s without ever observing the content change, so pixel \
                stability could not be confirmed. This is an environment problem (a machine too \
                loaded to complete render passes) or a view that renders no pixels (a zero-sized \
                frame) — not view motion; widening the settle budget won't fix it.
                """,
            )
        case .cancelled:
            // Deliberately quiet: a cancelled test is already being torn down and
            // a second issue would just bury the cancellation. Skipping the assert
            // outright is the real fix, tracked in TODOs.md.
            return
    }
}

/// Runs the settle phase a case declared: `.settled` waits for pixel-stable
/// renders (see ``settleContent(_:named:minDuration:maxDuration:timing:)``);
/// `.settledAtLeast` is the same loop with a raised `minDuration` floor (for
/// quiet-starting async chrome like the glass toolbar's material adaptation);
/// `.immediate` yields once — so a `.task` body that merely sets state
/// synchronously still runs — and re-lays-out, skipping the digest-render loop
/// entirely.
@MainActor
func settleForCapture(
    _ view: UIView,
    named name: String,
    settle: SnapshotSettle,
    timing: SnapshotCaptureTiming,
    timeoutPolicy: SnapshotSettleTimeoutPolicy,
) async -> SettleOutcome {
    switch settle {
        case .settled:
            return await settleContent(
                view,
                named: name,
                maxDuration: timeoutPolicy.maximumDuration(for: settle),
                timing: timing,
            )
        case let .settledAtLeast(minDuration):
            // Keep the hang budget for never-quiescing content above the raised
            // floor, so the minimum is always honored.
            return await settleContent(
                view,
                named: name,
                minDuration: minDuration,
                maxDuration: timeoutPolicy.maximumDuration(for: settle),
                timing: timing,
            )
        case .immediate:
            await Task.yield()
            CATransaction.performWithoutAnimation(view.layoutIfNeeded)
            return .skipped
    }
}

/// Suspends between render passes until the view's rendered content is stable —
/// two consecutive low-resolution renders are pixel-identical — giving SwiftUI
/// `.task`/async loads time to resolve, and finite animations (typewriter
/// reveals, `.transition` crossfades, launch transitions) time to run to
/// completion, before the capture. So content-loading screens snapshot their
/// loaded state, not a spinner, a half-revealed string, or a mid-fade frame.
///
/// This **must** suspend (`await Task.sleep`), not pump the run loop
/// synchronously: SwiftUI `.task` bodies are main-actor Swift-concurrency jobs
/// queued on the main dispatch queue, and the main queue is non-reentrant — a
/// nested `RunLoop.run()` from a synchronous main-actor test services timers and
/// CA commits but can never interleave those jobs, so `.task`-driven content
/// (CalendarView's month layout, TypewriterText's reveal) would never load no
/// matter how long it pumped. Suspending frees the main actor so they run.
///
/// Stability is judged on **pixels**, not layout flags: SwiftUI updates deep in
/// the hosted tree (an incremental text reveal, an opacity transition) don't mark
/// the root layer as needing layout, so a flag-based check reports "idle" while
/// an animation is mid-flight. Bounded by `minDuration` (always waited, so a
/// not-yet-scheduled `.task` still runs) and `maxDuration` (a view that never
/// quiesces — e.g. a repeating pulse — doesn't hang the capture).
///
/// `minDuration` also covers async appearance work that starts *quiet* and lands
/// late: the iOS 26 glass toolbar/tab bar adapts its material to the content
/// behind it a few hundred ms after hosting, so a floor below that captures the
/// pre-adaptation glass (seen on `primary`/`root` snapshots when the floor was
/// 50ms).
///
/// Stability compares each pass against the **anchor** (first sample of the
/// current quiet window), not just the previous pass, and requires the window to
/// span `stableQuietDuration`: at a 16ms cadence a slow transition (a glass
/// material crossfade) can quantize to zero between *adjacent* frames while
/// still drifting across the window — the anchor comparison catches the drift.
///
/// `maxDuration` budgets **observed motion**, not proof-of-stability. On a
/// starved machine a single pass (sleep + layout + render) can cost over a
/// second, so fewer than the three passes stability needs may fit in the
/// budget — and failing then would blame "content still changing" on content
/// that was never once seen to change (CI reproduced exactly that: the About
/// screen, static from its first frame, timed out ~50% of runs on a cold
/// loaded runner while its capture still matched the reference). So the
/// deadline only produces ``SettleOutcome/timedOut(budget:)`` when a change
/// was *observed* past anchor establishment; a change-free loop keeps running
/// until it can prove stability, giving up as
/// ``SettleOutcome/starved(passes:cap:)`` only at a hard cap several multiples
/// of the budget. Moving content can't slip through: any observed change past
/// the budget still fails, exactly as before.
@MainActor
@_spi(Testing) public func settleContent(
    _ view: UIView,
    named name: String,
    minDuration: TimeInterval = 0.25,
    maxDuration: TimeInterval = 2.5,
    timing: SnapshotCaptureTiming? = nil,
    mechanism: SnapshotSettleMechanism = .fromEnvironment,
) async -> SettleOutcome {
    // How long the rendered pixels must stay byte-identical to the quiet
    // window's anchor sample before the content counts as settled — matches the
    // old 2-passes-at-60ms quiet window, now sampled densely.
    let stableQuietDuration: Duration = .milliseconds(120)
    // How many multiples of the budget a change-free loop may spend proving
    // stability before giving up as starved. Generous on purpose: the cap only
    // gates runs that would otherwise fail falsely, and a genuinely moving view
    // is still bounded by `maxDuration` the moment a change is observed.
    let starvationHeadroom: Double = 4

    let clock = ContinuousClock()
    let start = clock.now
    let minDeadline = start.advanced(by: .seconds(minDuration))
    let maxDeadline = start.advanced(by: .seconds(maxDuration))
    let starvationDeadline = start.advanced(by: .seconds(maxDuration * starvationHeadroom))
    var anchorSample: Data?
    var anchorTime = start
    var stablePasses = 0
    var passCount = 0
    // One per mechanism, deliberately not shared. Both feed the `.timedOut` vs
    // `.starved` decision, and only the mechanism holding the verdict may
    // influence it — otherwise `both` mode could fail a capture that `pixel`
    // alone would have kept retrying, which would make the experiment change the
    // thing it exists to measure.
    var pixelObservedChange = false
    var quiescenceObservedChange = false
    // Reported on every exit path — including `.cancelled`, whose pass count is
    // exactly what distinguishes "gave up immediately" from "ground for 10s".
    defer { timing?.addSettlePasses(passCount) }

    let idleCounter = RunLoopIdleCounter()
    var lastIdleCount = 0
    var disagreements: [SettleDisagreement] = []
    var quiescentSince: ContinuousClock.Instant?
    var quiescentPasses = 0
    if mechanism != .pixel {
        idleCounter.start()
        lastIdleCount = idleCounter.idleCount
    }
    defer {
        idleCounter.stop()
        SnapshotSettleReporting.report(
            identifier: name,
            mechanism: mechanism,
            passes: passCount,
            disagreements: disagreements,
        )
    }

    while true {
        do {
            try await Task.sleep(for: .milliseconds(16))
        } catch {
            return .cancelled
        }
        // Sampled *before* this pass lays out, because the loop performs the
        // layout itself: read afterwards, `needsLayout` is always clear and that
        // third of the signal says nothing. Dirty layout here means something
        // changed since the previous pass, which is exactly the question.
        let hadPendingWorkBeforeLayout = mechanism == .pixel
            ? false
            : view.layer.hasPendingWork()

        CATransaction.performWithoutAnimation(view.layoutIfNeeded)
        passCount += 1

        // Quiescence: the run loop went idle at least once since the last pass
        // (so every runnable main-queue job drained), nothing was waiting to lay
        // out, and nothing in the captured subtree still needs display or is
        // animating.
        let isQuiescent: Bool? = if mechanism == .pixel {
            nil
        } else {
            {
                let idled = idleCounter.idleCount > lastIdleCount
                lastIdleCount = idleCounter.idleCount
                return idled
                    && !hadPendingWorkBeforeLayout
                    && !view.layer.hasPendingWork()
            }()
        }

        // Skipped entirely in `.quiescence` mode — not rendering it is the whole
        // point — so the expensive path only runs where its answer is used.
        let sample = mechanism == .quiescence ? nil : view.renderedContentSample()
        let now = clock.now

        var pixelSaysStable = false
        if mechanism != .quiescence {
            // Byte-exact on purpose — not the tolerance the final image compare
            // uses. The final compare answers "does this match the reference?",
            // where sub-pixel/gamut noise warrants a perceptual threshold. This
            // loop answers a different question — "has rendering *stopped
            // changing*?" — and the quarter-resolution sample already absorbs
            // sub-pixel jitter, so exact equality is the right settled signal. A
            // tolerance here would let a slow, still-drifting animation read as
            // settled between adjacent samples.
            if sample != nil, sample == anchorSample {
                stablePasses += 1
            } else {
                // The first non-nil sample merely establishes the anchor; only a
                // departure from an established anchor is the content changing.
                if anchorSample != nil {
                    pixelObservedChange = true
                }
                anchorSample = sample
                anchorTime = clock.now
                stablePasses = 0
            }
            pixelSaysStable = stablePasses >= 2
                && now >= anchorTime.advanced(by: stableQuietDuration)
        }

        var quiescenceSaysStable = false
        if mechanism != .pixel {
            if isQuiescent == true {
                if quiescentSince == nil { quiescentSince = now }
                quiescentPasses += 1
            } else {
                // Falling out of quiescence after having reached it is this
                // mechanism's equivalent of the pixels changing.
                if quiescentSince != nil { quiescenceObservedChange = true }
                quiescentSince = nil
                quiescentPasses = 0
            }
            quiescenceSaysStable = quiescentPasses >= 2
                && (quiescentSince.map { now >= $0.advanced(by: stableQuietDuration) } ?? false)
        }

        if mechanism == .both, quiescenceSaysStable != pixelSaysStable {
            disagreements.append(SettleDisagreement(
                pass: passCount,
                quiescenceWasEarlier: quiescenceSaysStable,
            ))
        }

        // `both` deliberately lets the digest keep the verdict — both the
        // "settled" call and the observed-change flag below — so running the
        // experiment can't change what any reference records.
        let isQuiescenceDeciding = mechanism == .quiescence
        let saysStable = isQuiescenceDeciding ? quiescenceSaysStable : pixelSaysStable
        let observedContentChange = isQuiescenceDeciding
            ? quiescenceObservedChange
            : pixelObservedChange
        if saysStable, now >= minDeadline {
            return .settled
        }
        // Checked after the stability check on purpose: a pass that completes
        // its proof late still settles rather than timing out — proven-stable
        // content is safe to capture no matter when the proof landed.
        if now >= maxDeadline {
            if observedContentChange {
                return .timedOut(budget: maxDuration)
            }
            if now >= starvationDeadline {
                return .starved(passes: passCount, cap: maxDuration * starvationHeadroom)
            }
        }
    }
}

extension UIView {
    /// A cheap content fingerprint: the view's pixels rendered at quarter
    /// resolution. Two byte-identical samples across passes mean the visible
    /// content stopped changing. Compared as full buffers, **never** by
    /// `hashValue` — a bridged `NSData` hash considers only a prefix of the
    /// bytes, so a text reveal below static top chrome would read "stable"
    /// mid-animation. `afterScreenUpdates: true` so each pass renders the
    /// current model state, not the last committed frame.
    @MainActor
    fileprivate func renderedContentSample() -> Data? {
        guard bounds.width >= 1, bounds.height >= 1 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 0.25
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(bounds: bounds, format: format).image { _ in
            drawHierarchy(in: bounds, afterScreenUpdates: true)
        }
        return image.cgImage?.dataProvider?.data as Data?
    }
}

/// Commits the pending Core Animation transaction, so any in-flight animation's
/// completion blocks — modal/transition settling — have run before the capture.
///
/// This used to run a zero-duration `UIView.animate` and pump the run loop until
/// its completion fired, with a 1-second timeout as the backstop. Instrumenting
/// the pipeline showed the completion **never** fired: the timeout was the only
/// exit on 50 of 50 captures, so every image paid a flat second — about 35% of
/// the whole snapshot suite — waiting for a callback that never arrived. An empty
/// animation block with nothing animatable in it gives UIKit no animation to
/// complete, and the doc comment's claim that re-enabling animations avoided
/// exactly that was simply wrong.
///
/// `CATransaction.flush()` expresses the actual intent directly and
/// synchronously. It is also close to redundant: the capture that immediately
/// follows renders with `afterScreenUpdates: true`, which commits the
/// transaction anyway. It is kept because that redundancy is not a guarantee —
/// the accessibility path re-lays-out between here and the render — and a commit
/// costs microseconds.
@MainActor
@_spi(Testing) public func drainInFlightAnimations() {
    CATransaction.flush()
}

extension UIView {
    /// Clears the tint color of every text input in the tree so the blinking caret
    /// doesn't flake captures. Not restored — capture hosts are transient.
    ///
    /// It walks the tree and targets only `UITextField`/`UITextView` rather than
    /// clearing the tint once at the root: `tintColor` inherits, so a clear root
    /// tint would also blank every control that draws with the accent tint —
    /// buttons, links, toggles, `Label` glyphs — silently changing the captured
    /// image. Only the text inputs (whose caret *is* the tint) may be cleared.
    @MainActor
    func hideTextInputCursors() {
        recursiveForEach(UITextField.self) { $0.tintColor = .clear }
        recursiveForEach(UITextView.self) { $0.tintColor = .clear }
    }

    @MainActor
    private func recursiveForEach<V: UIView>(_ type: V.Type, _ body: (V) -> Void) {
        if let matched = self as? V {
            body(matched)
        }
        for subview in subviews {
            subview.recursiveForEach(type, body)
        }
    }
}
