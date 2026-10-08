import Foundation

/// Inclusive whole-day bounds. Equal endpoints describe one estimate.
public struct DayBounds: Hashable, Sendable {
    public let lower: Int
    public let upper: Int

    public var isExact: Bool {
        lower == upper
    }

    public init(lower: Int, upper: Int) {
        precondition(lower >= 0 && lower <= upper, "Day bounds must be ordered and nonnegative.")
        self.lower = lower
        self.upper = upper
    }

    public init(exact days: Int) {
        self.init(lower: days, upper: days)
    }

    /// Keep one nearest-rounded estimate when exact; otherwise round outward.
    static func rounded(lowerNumerator: Int, upperNumerator: Int, denominator: Int) -> DayBounds {
        precondition(denominator > 0)
        if lowerNumerator == upperNumerator {
            return DayBounds(exact: (lowerNumerator + denominator / 2) / denominator)
        }
        return DayBounds(
            lower: lowerNumerator / denominator,
            upper: (upperNumerator + denominator - 1) / denominator,
        )
    }
}
