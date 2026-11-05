import Foundation

/// A nonempty half-open validity interval. A nil end explicitly means ongoing; finite history
/// queries continue to use `RecordingPeriod` and clip ongoing validity at their own boundary.
public struct RecordingInterval: Hashable, Codable, Sendable, Comparable {
    public enum ValidationError: Error { case invalidBounds }

    public let start: Date
    public let end: Date?

    public init(start: Date, end: Date?) throws {
        guard start.timeIntervalSinceReferenceDate.isFinite,
              end.map({ $0.timeIntervalSinceReferenceDate.isFinite && start < $0 }) ?? true
        else { throw ValidationError.invalidBounds }
        self.start = start
        self.end = end
    }

    public init(_ period: RecordingPeriod) throws {
        try period.validate()
        try self.init(start: period.start, end: period.end)
    }

    public func validate() throws {
        _ = try Self(start: start, end: end)
    }

    public func contains(_ instant: Date) -> Bool {
        start <= instant && (end.map { instant < $0 } ?? true)
    }

    public func overlaps(_ other: Self) -> Bool {
        (other.end.map { start < $0 } ?? true) && (end.map { other.start < $0 } ?? true)
    }

    public func intersection(_ other: Self) -> Self? {
        guard overlaps(other) else { return nil }
        return Self(validStart: max(start, other.start), end: Self.earlier(end, other.end))
    }

    public func intersection(_ query: RecordingPeriod) -> RecordingPeriod? {
        let start = max(start, query.start)
        let end = min(end ?? query.end, query.end)
        guard start < end else { return nil }
        // Both bounds come from validated intervals; the query always supplies a finite end.
        return RecordingPeriod(validStart: start, end: end)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.start != rhs.start { return lhs.start < rhs.start }
        switch (lhs.end, rhs.end) {
            case let (.some(left), .some(right)): return left < right
            case (.some, .none): return true
            case (.none, .some), (.none, .none): return false
        }
    }

    /// Union overlaps and touching boundaries without filling gaps or inventing an end.
    public static func union(_ intervals: [Self]) -> [Self] {
        var result: [Self] = []
        for interval in intervals.sorted() {
            if let last = result.last, last.end.map({ interval.start <= $0 }) ?? true {
                let end: Date? = if let left = last.end, let right = interval.end {
                    max(left, right)
                } else { nil }
                result[result.count - 1] = Self(validStart: last.start, end: end)
            } else {
                result.append(interval)
            }
        }
        return result
    }

    private static func earlier(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
            case let (.some(left), .some(right)): min(left, right)
            case let (.some(value), .none), let (.none, .some(value)): value
            case (.none, .none): nil
        }
    }

    private init(validStart: Date, end: Date?) {
        start = validStart
        self.end = end
    }
}
