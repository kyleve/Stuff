import Foundation

/// Events emitted by Periscope's own delivery and persistence machinery.
@LogScope("Periscope")
public enum PeriscopeInternalLog {
    /// Reports records discarded by the bounded delivery queue.
    @LogEvent("dropped-events", level: .warning)
    public struct DroppedEvents {
        @LogField("count", exposure: .shareable, kind: .count)
        public var count: Int

        public var message: String {
            "\(count) log event(s) dropped before delivery"
        }
    }

    /// Marks a failed, rolled-back store write in the durable history.
    @LogEvent("store-write-failed", level: .warning)
    public struct StoreWriteFailed {
        @LogField("lost_record_count", exposure: .shareable, kind: .count)
        public var lostRecordCount: Int

        @LogField("reason", exposure: .restricted, kind: .errorDetails)
        public var reason: String

        public var message: String {
            "\(lostRecordCount) record(s) failed to persist: \(reason)"
        }
    }
}

public typealias StoreWriteFailed = PeriscopeInternalLog.StoreWriteFailed
