import Foundation
import Network
import os

/// Logs network path changes (`NWPathMonitor`) — connectivity loss,
/// airplane-mode-style transitions, and interface changes (Wi-Fi ↔
/// cellular).
public struct NetworkPathAmbientSource: AmbientEventSource {
    /// The running monitor; boxed so the source stays a Sendable value.
    private let monitor = OSAllocatedUnfairLock<NWPathMonitor?>(uncheckedState: nil)

    public init() {}

    public func start(log: Log<AmbientEvent>) {
        let started = NWPathMonitor()
        started.pathUpdateHandler = { path in
            log { AmbientEvent(kind: .network, value: Self.describe(path)) }
        }
        started.start(queue: DispatchQueue(label: "com.stuff.periscope.network-path"))
        let previous = monitor.withLockUnchecked { boxed -> NWPathMonitor? in
            let previous = boxed
            boxed = started
            return previous
        }
        // A repeated start replaces the monitor; without the cancel the old
        // one would keep running (and logging) forever.
        previous?.cancel()
    }

    public func stop() {
        let running = monitor.withLockUnchecked { boxed -> NWPathMonitor? in
            let running = boxed
            boxed = nil
            return running
        }
        running?.cancel()
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
