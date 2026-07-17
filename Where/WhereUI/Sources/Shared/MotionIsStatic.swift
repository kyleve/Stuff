import SnapshotKit
import SwiftUI

/// Answers the one question a view with continuous or looping motion (a
/// repeat-forever pulse, a `TimelineView(.animation)` sweep, a typewriter
/// reveal) must ask: should it render its deterministic static end-state
/// instead of animating?
///
/// `true` when the user prefers Reduce Motion **or** the view is being
/// captured for a snapshot (`\.isCapturingSnapshot`) — motion that never
/// settles can't be pixel-stable, so captures pin it the same way Reduce
/// Motion does. Consult this wrapper instead of hand-rolling the two
/// environment reads, so the definition of "static" stays in one place:
///
/// ```swift
/// @MotionIsStatic private var motionIsStatic
///
/// guard !motionIsStatic else { return }
/// withAnimation(.easeInOut.repeatForever()) { pulsing = true }
/// ```
@propertyWrapper
struct MotionIsStatic: DynamicProperty {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isCapturingSnapshot) private var isCapturingSnapshot

    var wrappedValue: Bool {
        reduceMotion || isCapturingSnapshot
    }
}
