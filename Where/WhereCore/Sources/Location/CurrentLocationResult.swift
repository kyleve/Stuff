import Foundation

/// The explicit outcome of a bounded one-shot foreground location request.
public enum CurrentLocationResult: Sendable, Equatable {
    /// Why Core Location could not provide a usable one-shot result.
    public enum UnavailableReason: Sendable, Equatable {
        case authorizationUnavailable(LocationAuthorizationStatus)
        case preciseLocationDisabled
        case timeout
        case providerFailure
        case cancellation
    }

    case success(LocationSample)
    case unavailable(UnavailableReason)

    /// The captured sample, when acquisition succeeded.
    public var sample: LocationSample? {
        guard case let .success(sample) = self else { return nil }
        return sample
    }
}
