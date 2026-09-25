import PeriscopeCore

/// Names `DataIssueScanner`'s timed spans, and nothing else — the scanner throws
/// its read failures to the caller, so what's worth recording about it is what a
/// scan costs. A span-only facade, like ``PresenceCalendarLog``.
@LogScope("DataIssueScanner")
enum DataIssueScannerLog {
    /// Names the scan spans (`log.measure(.scan) { … }`).
    ///
    /// `description` is written out because ``detect(_:)`` carries the detector's
    /// category: reflection would render it
    /// `detect(WhereCore.DataIssueCategory.borderDrift)`, leaking the module into
    /// a name the tools group timings by.
    enum SpanName: Hashable, CustomStringConvertible {
        /// A full scan on a cache miss: the reads, then every detector.
        case scan
        /// One detector's pass over the already-read input, so a scan that runs
        /// long attributes to the detector responsible rather than to "the scan".
        case detect(DataIssueCategory)

        var description: String {
            switch self {
                case .scan: "scan"
                case let .detect(category): "detect(\(category.name))"
            }
        }
    }
}

extension DataIssueCategory {
    /// The category's stable name, for span names and diagnostics. Spelled out
    /// rather than reflected so renaming a Swift case is a deliberate change to
    /// recorded history, not a silent one.
    var name: String {
        switch self {
            case .missingDays: "missing-days"
            case .borderDrift: "border-drift"
            case .abruptChange: "abrupt-change"
            case .flightDay: "flight-day"
        }
    }
}
