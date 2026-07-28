import Foundation

/// Logs Low Power Mode at start and on every transition — background work
/// behaves differently under it, which matters when diagnosing "it only
/// breaks sometimes".
public final class LowPowerModeAmbientSource: NotificationAmbientSource {
    override public var observedNames: [Notification.Name] {
        [.NSProcessInfoPowerStateDidChange]
    }

    override public func event(for _: Notification) -> AmbientEvent? {
        Self.currentEvent()
    }

    /// A session that runs entirely in (or entirely out of) Low Power Mode
    /// never posts a transition, so without this baseline the ambient
    /// snapshot would have no power mode at all. `ProcessInfo` is
    /// nonisolated, so the read needs no actor hop.
    override public func started() {
        emit(Self.currentEvent())
    }

    private static func currentEvent() -> AmbientEvent {
        let enabled = ProcessInfo.processInfo.isLowPowerModeEnabled
        return AmbientEvent(kind: .powerMode, value: enabled ? "low-power" : "normal")
    }
}
