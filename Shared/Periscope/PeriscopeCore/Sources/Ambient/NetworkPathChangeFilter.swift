import Foundation
import os

/// Collapses a stream of network-path descriptions to change-only events.
///
/// `NWPathMonitor` re-fires its update handler on churn that maps to the
/// same coarse description — interface reordering, `isExpensive` /
/// `isConstrained` flips, DNS/gateway changes, routine path re-evaluation —
/// and logging every callback floods the ambient log with duplicate
/// `network:` entries. This filter returns an event only when the value
/// actually changes from the last emitted one; consecutive duplicates are
/// dropped.
///
/// It only drops *consecutive* duplicates: a value that recurs after a
/// different one in between still emits, so genuine flapping (wifi ↔
/// cellular) is preserved. A reference type so a source struct can share one
/// filter across monitor restarts.
///
/// `@_spi(Testing) public` because it exists purely so
/// `NetworkPathAmbientSource` can be tested for coalescing without driving a
/// live `NWPathMonitor` (whose `NWPath` values can't be constructed in a
/// test).
@_spi(Testing) public final class NetworkPathChangeFilter: Sendable {
    private let lastDescription = OSAllocatedUnfairLock<String?>(initialState: nil)

    public init() {}

    /// The event to log for `description`, or `nil` when it is unchanged
    /// since the last emitted value.
    public func event(for description: String) -> AmbientEvent? {
        lastDescription.withLock { last in
            guard last != description else { return nil }
            last = description
            return AmbientEvent(kind: .network, value: description)
        }
    }

    /// Forget the last value so the next description re-reports. Used on
    /// (re)start so a restart re-emits current connectivity rather than
    /// silently swallowing it as a duplicate of a prior run.
    public func reset() {
        lastDescription.withLock { $0 = nil }
    }
}
