import Foundation

public struct ImageSelector: Sendable {
    public init() {}
    public func select(from sequence: CaptureSequence) throws -> CapturedImage {
        let candidates = sequence.images.filter {
            if case let .scored(score) = $0
                .score { return !score.isUtility && score.overall.isFinite }
            return false
        }
        guard let best = candidates.sorted(by: { lhs, rhs in
            guard case let .scored(left) = lhs.score,
                  case let .scored(right) = rhs.score else { return false }
            if left.overall != right.overall { return left.overall > right.overall }
            let ld = abs(lhs.capturedAt.timeIntervalSince(sequence.event.date))
            let rd = abs(rhs.capturedAt.timeIntervalSince(sequence.event.date))
            if ld != rd { return ld < rd }
            return lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString
        }).first else { throw DaylightError.noScoredImages }
        return best
    }
}
