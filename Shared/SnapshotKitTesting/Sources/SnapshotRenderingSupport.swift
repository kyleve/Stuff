import SnapshotKit
import SwiftUI
import Testing
import UIKit

/// How a settle phase ended. Only ``settled`` and ``skipped`` mean the pixels
/// the capture is about to record are the ones the case declared — the rest
/// describe a capture the pipeline can't vouch for, so callers report them
/// instead of quietly proceeding.
enum SettleOutcome: Equatable {
    /// Renders reached pixel stability and held it through the quiet window.
    case settled
    /// The case declared `.immediate`, so no settle loop ran.
    case skipped
    /// The budget elapsed with the content still changing. Whatever gets
    /// captured is an arbitrary frame of whatever is still in motion, which is
    /// how a flaky reference gets recorded.
    case timedOut(budget: TimeInterval)
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
) {
    switch outcome {
        case .settled, .skipped:
            return
        case let .timedOut(budget):
            Issue.record(
                """
                Snapshot content never settled: the \(phase) phase for \
                \(type(of: viewController)) was still changing after \(budget.formatted())s, \
                so this capture is an arbitrary frame of whatever is still moving. Freeze the \
                motion at a deterministic phase behind `\\.isCapturingSnapshot` (the Where app \
                does this with `MotionIsStatic`), or — if the content is merely slow rather than \
                endless — raise the floor with `.settledAtLeast(minDuration:)`.
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
/// renders (see ``settleContent(_:minDuration:maxDuration:)``);
/// `.settledAtLeast` is the same loop with a raised `minDuration` floor (for
/// quiet-starting async chrome like the glass toolbar's material adaptation);
/// `.immediate` yields once — so a `.task` body that merely sets state
/// synchronously still runs — and re-lays-out, skipping the digest-render loop
/// entirely.
@MainActor
func settleForCapture(_ view: UIView, settle: SnapshotSettle) async -> SettleOutcome {
    switch settle {
        case .settled:
            return await settleContent(view)
        case let .settledAtLeast(minDuration):
            // Keep the hang budget for never-quiescing content above the raised
            // floor, so the minimum is always honored.
            return await settleContent(
                view,
                minDuration: minDuration,
                maxDuration: max(2.5, minDuration + 2.5),
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
/// Returns how it ended: exhausting `maxDuration` means the content never
/// stopped moving, which the caller reports rather than capturing an arbitrary
/// frame and calling it a reference.
@MainActor
func settleContent(
    _ view: UIView,
    minDuration: TimeInterval = 0.25,
    maxDuration: TimeInterval = 2.5,
) async -> SettleOutcome {
    // How long the rendered pixels must stay byte-identical to the quiet
    // window's anchor sample before the content counts as settled — matches the
    // old 2-passes-at-60ms quiet window, now sampled densely.
    let stableQuietDuration: TimeInterval = 0.12

    let start = Date()
    let minDeadline = start.addingTimeInterval(minDuration)
    let maxDeadline = start.addingTimeInterval(maxDuration)
    var anchorSample: Data?
    var anchorDate = Date()
    var stablePasses = 0
    while Date() < maxDeadline {
        do {
            try await Task.sleep(for: .milliseconds(16))
        } catch {
            return .cancelled
        }
        CATransaction.performWithoutAnimation(view.layoutIfNeeded)
        let sample = view.renderedContentSample()
        // Byte-exact on purpose — not the tolerance the final image compare uses.
        // The final compare answers "does this match the reference?", where
        // sub-pixel/gamut noise warrants a perceptual threshold. This loop answers
        // a different question — "has rendering *stopped changing*?" — and the
        // quarter-resolution sample already absorbs sub-pixel jitter, so exact
        // equality is the right settled signal. A tolerance here would let a slow,
        // still-drifting animation read as settled between adjacent samples.
        if sample != nil, sample == anchorSample {
            stablePasses += 1
        } else {
            anchorSample = sample
            anchorDate = Date()
            stablePasses = 0
        }
        if stablePasses >= 2,
           Date() >= anchorDate.addingTimeInterval(stableQuietDuration),
           Date() >= minDeadline
        {
            return .settled
        }
    }
    return .timedOut(budget: maxDuration)
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

/// Runs a zero-duration animation and pumps the run loop until its completion
/// fires (or `timeout` elapses), so any in-flight animation's completion blocks —
/// modal/transition settling — have run before the capture. Best-effort: returns
/// whether it settled within the budget.
///
/// Animations are forced on for the flush itself (restored after): the completion
/// block of a zero-duration `UIView.animate` won't fire while animations are
/// globally disabled, which would otherwise burn the whole `timeout` every call.
@MainActor
@discardableResult
func drainInFlightAnimations(timeout: TimeInterval = 1) -> Bool {
    let animationsWereEnabled = UIView.areAnimationsEnabled
    UIView.setAnimationsEnabled(true)
    defer { UIView.setAnimationsEnabled(animationsWereEnabled) }

    var completed = false
    UIView.animate(withDuration: 0) {} completion: { _ in completed = true }

    let deadline = Date(timeIntervalSinceNow: timeout)
    while !completed {
        if Date() > deadline { return false }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.001))
    }
    return true
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
