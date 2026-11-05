import Foundation

/// A finite, nonempty half-open interval. Adjacent choices never claim the same instant.
public struct RecordingPeriod: Hashable, Codable, Sendable, Comparable {
    public enum ValidationError: Error {
        case invalidBounds
    }

    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) throws {
        guard start.timeIntervalSinceReferenceDate.isFinite,
              end.timeIntervalSinceReferenceDate.isFinite,
              start < end
        else { throw ValidationError.invalidBounds }
        self.start = start
        self.end = end
    }

    /// Store and archive admission validate synthesized wire values before use.
    public func validate() throws {
        _ = try Self(start: start, end: end)
    }

    public func contains(_ instant: Date) -> Bool {
        start <= instant && instant < end
    }

    public func overlaps(_ other: Self) -> Bool {
        start < other.end && other.start < end
    }

    public func intersection(_ other: Self) -> Self? {
        guard overlaps(other) else { return nil }
        return Self(validStart: max(start, other.start), end: min(end, other.end))
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.start != rhs.start { return lhs.start < rhs.start }
        return lhs.end < rhs.end
    }

    /// Union overlapping or adjacent ranges without bridging a gap.
    public static func union(_ periods: [Self]) -> [Self] {
        var result: [Self] = []
        for period in periods.sorted() {
            if let last = result.last, period.start <= last.end {
                result[result.count - 1] = Self(
                    validStart: last.start,
                    end: max(last.end, period.end),
                )
            } else {
                result.append(period)
            }
        }
        return result
    }

    init(validStart: Date, end: Date) {
        start = validStart
        self.end = end
    }
}
