import Foundation

/// Logs the thermal state at start and on every change; `serious` and
/// `critical` log at `.warning` since the system is about to start
/// throttling.
public final class ThermalStateAmbientSource: NotificationAmbientSource {
    override public var observedNames: [Notification.Name] {
        [ProcessInfo.thermalStateDidChangeNotification]
    }

    override public func event(for _: Notification) -> AmbientEvent? {
        Self.event(for: ProcessInfo.processInfo.thermalState)
    }

    /// A device that launches hot and stays hot never posts a change
    /// notification, so without this baseline the ambient snapshot would
    /// claim to know nothing about the thermal state for the whole session.
    /// `ProcessInfo` is nonisolated, so the read needs no actor hop.
    override public func started() {
        emit(Self.event(for: ProcessInfo.processInfo.thermalState))
    }

    /// The ambient event for a given thermal state — exposed for tests via
    /// `@_spi(Testing)` so the mapping stays asserted.
    @_spi(Testing) public static func event(for state: ProcessInfo.ThermalState) -> AmbientEvent {
        let value: String
        let level: LogLevel
        switch state {
            case .nominal:
                value = "nominal"
                level = .info
            case .fair:
                value = "fair"
                level = .info
            case .serious:
                value = "serious"
                level = .warning
            case .critical:
                value = "critical"
                level = .warning
            @unknown default:
                value = "unknown"
                level = .info
        }
        return AmbientEvent(kind: .thermalState, value: value, level: level)
    }
}
