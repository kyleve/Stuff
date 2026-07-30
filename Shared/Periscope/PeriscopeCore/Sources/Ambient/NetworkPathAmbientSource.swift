import Foundation
import Network
import os

/// Logs network path changes (`NWPathMonitor`) — connectivity loss,
/// airplane-mode-style transitions, and interface changes (Wi-Fi ↔
/// cellular).
///
/// `NWPathMonitor` re-fires on churn that maps to the same coarse
/// description — interface reordering, `isExpensive`/`isConstrained` flips,
/// DNS/gateway changes, routine path re-evaluation — so logging every
/// callback floods the log with duplicate `network:` entries. This keeps
/// the last description it emitted and logs **change-only**: only
/// *consecutive* duplicates are dropped, so genuine flapping (Wi-Fi ↔
/// cellular) still logs; a (re)start re-reports current connectivity.
public final class NetworkPathAmbientSource: AmbientEventSource {
    /// The running monitor plus the last value emitted, guarded together
    /// so a restart can swap the monitor and reset the filter atomically.
    /// Boxed in a lock because path updates arrive on the monitor's queue
    /// while `start`/`stop` run on the caller's.
    private struct State {
        var monitor: NWPathMonitor?
        var lastValue: [String: AmbientValue]?
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
            state.lastValue = nil
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
            state.lastValue = nil
            return running
        }
        running?.cancel()
    }

    /// Log `value` only when it differs from the last one emitted — the
    /// change-only filter that keeps chatty `NWPathMonitor` updates from
    /// flooding the log. Exposed for tests via `@_spi(Testing)` so the
    /// coalescing is covered without a live monitor (an `NWPath` can't be
    /// constructed in a test).
    @_spi(Testing) public func emit(_ value: [String: AmbientValue], to log: Log<AmbientEvent>) {
        let changed = state.withLockUnchecked { state -> Bool in
            guard state.lastValue != value else { return false }
            state.lastValue = value
            return true
        }
        guard changed else { return }
        log { AmbientEvent(kind: .network, value: value) }
    }

    private static func describe(_ path: NWPath) -> [String: AmbientValue] {
        switch path.status {
            case .satisfied:
                let interfaces = path.availableInterfaces.map(\.type.ambientName)
                return [
                    "status": .string("satisfied"),
                    "interfaces": .string(interfaces.joined(separator: ", ")),
                ]
            case .unsatisfied:
                return ["status": .string("unsatisfied")]
            case .requiresConnection:
                return ["status": .string("requires-connection")]
            @unknown default:
                return ["status": .string("unknown")]
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
