import WhereCore

/// Scope composition selects whether events describe the real installation or a demo world.
@MainActor
protocol ScopeCompatibilityEvents {
    var permitsVersionPublication: Bool { get }
    func changes() -> AsyncStream<Void>
    func deviceRemoved(_ deviceID: RecordingDeviceID)
}

struct InstallationCompatibilityEvents: ScopeCompatibilityEvents {
    let services: WhereServices
    let coordinator: DataCompatibilityCoordinator
    let permitsVersionPublication = true

    func changes() -> AsyncStream<Void> {
        services.remoteDataChangeUpdates()
    }

    func deviceRemoved(_ deviceID: RecordingDeviceID) {
        coordinator.recordRemoval(of: deviceID)
    }
}

struct NoopScopeCompatibilityEvents: ScopeCompatibilityEvents {
    let permitsVersionPublication = false
    func changes() -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }

    func deviceRemoved(_: RecordingDeviceID) {}
}
