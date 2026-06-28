import Foundation

enum WhereCoreTestSupport {
    static let pacific = TimeZone(identifier: "America/Los_Angeles")!

    static func calendar(timeZone: TimeZone = pacific) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    static func iso(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string) ?? Date(timeIntervalSince1970: 0)
    }
}

/// A hand-advanced, thread-safe clock for tests that inject a `now` closure
/// (e.g. `WhereServices`, `DataIssueScanner`, `WidgetSnapshotPublisher`): read
/// `now` from the closure while the test drives time forward with `advance(by:)`.
/// Shared so the per-suite copies don't drift.
final class MutableClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date) {
        current = start
    }

    var now: Date {
        lock.withLock { current }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock { current += interval }
    }
}
