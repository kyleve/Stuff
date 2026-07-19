import Foundation

/// Logs thermal state changes; `serious` and `critical` log at `.warning`
/// since the system is about to start throttling.
public final class ThermalStateAmbientSource: AmbientEventSource {
    private let tokens = AmbientObserverTokens()

    public init() {}

    public func start(log: Log<AmbientEvent>) {
        let token = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: nil,
        ) { _ in
            log { Self.event(for: ProcessInfo.processInfo.thermalState) }
        }
        tokens.replace(with: [token])
    }

    public func stop() {
        tokens.removeAll()
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
