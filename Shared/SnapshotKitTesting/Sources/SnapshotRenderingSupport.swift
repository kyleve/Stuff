import SwiftUI
import UIKit

/// A hosting controller that can be driven to a stable size before measurement.
@MainActor
protocol StableSizingHostingController: AnyObject {
    /// Pumps the run loop until the reported size stops changing (SwiftUI can need
    /// several state/layout passes to reach its final size), bounded by a small
    /// loop budget.
    func waitForStableSize(constrainedTo size: CGSize)
}

extension UIHostingController: StableSizingHostingController {
    func waitForStableSize(constrainedTo constrainedSize: CGSize) {
        let maxLoops = 5
        let initialSize = view.sizeThatFits(constrainedSize)
        var currentSize = initialSize
        var loops = 0
        while currentSize == initialSize, loops < maxLoops {
            RunLoop.current.run(until: Date())
            currentSize = view.sizeThatFits(constrainedSize)
            loops += 1
        }
    }
}

/// Runs a zero-duration animation and pumps the run loop until its completion
/// fires (or `timeout` elapses), so any in-flight animation's completion blocks —
/// modal/transition settling — have run before the capture. Best-effort: returns
/// whether it settled within the budget.
@MainActor
@discardableResult
func drainInFlightAnimations(timeout: TimeInterval = 5) -> Bool {
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
