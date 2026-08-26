import Foundation

/// The honest controller-visible state of one projection experience runtime.
public enum FeedHealth: Equatable, Sendable {
    case idle
    case loading
    case healthy(lastUpdate: Date, visibleContentCount: Int)
    case retrying(
        lastUpdate: Date?,
        nextRetry: Date,
        failure: ThrowFailureCategory,
        visibleContentCount: Int,
    )
    case failed(ThrowFailureCategory)
    case quiet

    public var visibleContentCount: Int {
        switch self {
            case let .healthy(_, visibleContentCount), let .retrying(_, _, _, visibleContentCount):
                visibleContentCount
            case .idle, .loading, .failed, .quiet:
                0
        }
    }
}
