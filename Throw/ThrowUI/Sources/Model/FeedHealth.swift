import Foundation

/// The honest controller-visible state of the selected aircraft feed.
public enum FeedHealth: Equatable, Sendable {
    case idle
    case loading
    case healthy(lastUpdate: Date, visibleAircraft: Int)
    case retrying(
        lastUpdate: Date?,
        nextRetry: Date,
        failure: ThrowFailureCategory,
        visibleAircraft: Int,
    )
    case failed(ThrowFailureCategory)
    case quiet

    public var visibleAircraft: Int {
        switch self {
            case let .healthy(_, visibleAircraft), let .retrying(_, _, _, visibleAircraft):
                visibleAircraft
            case .idle, .loading, .failed, .quiet:
                0
        }
    }
}
