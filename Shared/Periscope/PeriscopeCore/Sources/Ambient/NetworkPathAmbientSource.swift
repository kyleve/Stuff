import Foundation
import Network
import os

/// Logs network path changes (`NWPathMonitor`) — connectivity loss,
/// airplane-mode-style transitions, and interface changes (Wi-Fi ↔
/// cellular).
///
/// A reference type: it owns its observation *and* the last description it
/// logged, so it can filter `NWPathMonitor`'s frequent, change-agnostic
/// updates down to real transitions before emitting. The monitor re-fires
/// on churn that maps to the same coarse description — interface
/// reordering, `isExpensive`/`isConstrained` flips, DNS/gateway changes,
/// routine path re-evaluation — and logging each callback would flood the
/// ambient log with duplicate `network:` entries. Only *consecutive*
/// duplicates are dropped, so genuine flapping (Wi-Fi ↔ cellular) still
/// logs; a (re)start re-reports current connectivity.
public final class NetworkPathAmbientSource: AmbientEventSource {
    /// The running monitor plus the last description emitted, guarded
    /// together so a restart can swap the monitor and reset the filter
    /// atomically. Boxed in a lock because path updates arrive on the
    /// monitor's queue while `start`/`stop` run on the caller's.
    private struct State {
        var monitor: NWPathMonitor?
        var lastDescription: String?
    }

    private let state = OSAllocatedUnfairLock<State>(uncheckedState: State())

    public init() {}

    public func start(log: Log<AmbientEvent>) {
        let started = NWPathMonitor()
        started.pathUpdateHandler = { [weak self] path in
            self?.emit(Self.describe(path), to: log)
        }
        // Swap in the new monitor and reset the filter so a restart
        // re-reports current connectivity rather than swallowing it as a
        // duplicate of the prior run.
        let previous = state.withLockUnchecked { state -> NWPathMonitor? in
            let previous = state.monitor
            state.monitor = started
            state.lastDescription = nil
            return previous
        }
        // A repeated start replaces the monitor; without the cancel the old
        // one would keep running (and logging) forever.
        previous?.cancel()
        started.start(queue: DispatchQueue(label: "com.stuff.periscope.network-path"))
    }

    public func stop() {
        let running = state.withLockUnchecked { state -> NWPathMonitor? in
            let running = state.monitor
            state.monitor = nil
            state.lastDescription = nil
            return running
        }
        running?.cancel()
    }

    /// Log `description` only when it differs from the last one emitted —
    /// the change-only filter that keeps chatty `NWPathMonitor` updates
    /// from flooding the log. Exposed for tests via `@_spi(Testing)` so the
    /// coalescing is covered without a live monitor (an `NWPath` can't be
    /// constructed in a test).
    @_spi(Testing) public func emit(_ description: String, to log: Log<AmbientEvent>) {
        let changed = state.withLockUnchecked { state -> Bool in
            guard state.lastDescription != description else { return false }
            state.lastDescription = description
            return true
        }
        guard changed else { return }
        log { AmbientEvent(kind: .network, value: description) }
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
