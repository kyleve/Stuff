import Foundation
import Network
import os

/// Logs network path changes (`NWPathMonitor`) — connectivity loss,
/// airplane-mode-style transitions, and interface changes (Wi-Fi ↔
/// cellular).
public struct NetworkPathAmbientSource: AmbientEventSource {
    /// The running monitor; boxed so the source stays a Sendable value.
    private let monitor = OSAllocatedUnfairLock<NWPathMonitor?>(uncheckedState: nil)
    /// Coalesces the monitor's frequent, change-agnostic updates down to
    /// the transitions worth logging (see ``NetworkPathChangeFilter``).
    private let filter = NetworkPathChangeFilter()

    public init() {}

    public func start(log: Log<AmbientEvent>) {
        let started = NWPathMonitor()
        let filter = filter
        started.pathUpdateHandler = { path in
            // NWPathMonitor re-fires on churn that maps to the same
            // description; only log when the value we'd record changes.
            guard let event = filter.event(for: Self.describe(path)) else { return }
            log { event }
        }
        let previous = monitor.withLockUnchecked { boxed -> NWPathMonitor? in
            let previous = boxed
            boxed = started
            return previous
        }
        // A repeated start replaces the monitor; without the cancel the old
        // one would keep running (and logging) forever.
        previous?.cancel()
        // A restart re-reports current connectivity rather than swallowing
        // it as a duplicate of the prior run.
        filter.reset()
        started.start(queue: DispatchQueue(label: "com.stuff.periscope.network-path"))
    }

    public func stop() {
        let running = monitor.withLockUnchecked { boxed -> NWPathMonitor? in
            let running = boxed
            boxed = nil
            return running
        }
        running?.cancel()
        filter.reset()
    }

    private static func describe(_ path: NWPath) -> String {
        switch path.status {
            case .satisfied:
                let interfaces = path.availableInterfaces.map(\.type.ambientName)
                return "satisfied (\(interfaces.joined(separator: ", ")))"
            case .unsatisfied:
                return "unsatisfied"
            case .requiresConnection:
                return "requires-connection"
            @unknown default:
                return "unknown"
        }
    }
}

extension NWInterface.InterfaceType {
    fileprivate var ambientName: String {
        switch self {
            case .wifi: "wifi"
            case .cellular: "cellular"
            case .wiredEthernet: "wired"
            case .loopback: "loopback"
            case .other: "other"
            @unknown default: "unknown"
        }
    }
}
