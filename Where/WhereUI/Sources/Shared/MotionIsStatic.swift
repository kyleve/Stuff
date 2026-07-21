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
///
/// `@Environment` reads work here because the wrapper is a `DynamicProperty`:
/// SwiftUI walks a view's `DynamicProperty` members (including nested ones) and
/// populates their environment before `body`, so the two reads resolve exactly
/// as they would on the view itself. Proven end-to-end by the `launchSplash.*`
/// captures (the pulse/radar freeze only if this reads the capture flag) and by
/// `WhereUISnapshotTests.SnapshotCaptureFlagProbeTests`.
@propertyWrapper
struct MotionIsStatic: DynamicProperty {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isCapturingSnapshot) private var isCapturingSnapshot

    var wrappedValue: Bool {
        reduceMotion || isCapturingSnapshot
    }
}
