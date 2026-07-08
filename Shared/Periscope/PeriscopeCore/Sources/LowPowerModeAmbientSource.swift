import Foundation

/// Logs Low Power Mode transitions — background work behaves differently
/// under it, which matters when diagnosing "it only breaks sometimes".
public struct LowPowerModeAmbientSource: AmbientEventSource {
    public init() {}

    public func start(log: Log<AmbientEvent>) {
        _ = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: nil,
        ) { _ in
            let enabled = ProcessInfo.processInfo.isLowPowerModeEnabled
            log { AmbientEvent(kind: .powerMode, value: enabled ? "low-power" : "normal") }
        }
    }
}
