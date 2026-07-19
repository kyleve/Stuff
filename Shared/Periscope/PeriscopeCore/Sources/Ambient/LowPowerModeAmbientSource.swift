import Foundation

/// Logs Low Power Mode transitions — background work behaves differently
/// under it, which matters when diagnosing "it only breaks sometimes".
public final class LowPowerModeAmbientSource: NotificationAmbientSource {
    override public var observedNames: [Notification.Name] {
        [.NSProcessInfoPowerStateDidChange]
    }

    override public func event(for _: Notification) -> AmbientEvent? {
        let enabled = ProcessInfo.processInfo.isLowPowerModeEnabled
        return AmbientEvent(kind: .powerMode, value: enabled ? "low-power" : "normal")
    }
}
