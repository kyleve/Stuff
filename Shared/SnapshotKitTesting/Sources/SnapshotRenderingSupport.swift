import SwiftUI
import UIKit

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
@MainActor
func settleContent(
    _ view: UIView,
    minDuration: TimeInterval = 0.05,
    maxDuration: TimeInterval = 2.5,
) async {
    let start = Date()
    let minDeadline = start.addingTimeInterval(minDuration)
    let maxDeadline = start.addingTimeInterval(maxDuration)
    var previousSample: Data?
    var stablePasses = 0
    while Date() < maxDeadline {
        do {
            try await Task.sleep(for: .milliseconds(60))
        } catch {
            break // Cancelled — stop settling; the capture proceeds as-is.
        }
        CATransaction.performWithoutAnimation(view.layoutIfNeeded)
        let sample = view.renderedContentSample()
        stablePasses = sample != nil && sample == previousSample ? stablePasses + 1 : 0
        previousSample = sample
        if stablePasses >= 2, Date() >= minDeadline { break }
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
