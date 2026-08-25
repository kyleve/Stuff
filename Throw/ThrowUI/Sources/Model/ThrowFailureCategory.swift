/// A redacted, actionable category suitable for UI and accessibility copy.
public enum ThrowFailureCategory: Equatable, Sendable {
    case sourceNotValidated
    case missingCredential
    case invalidCredential
    case subscription
    case entitlement
    case quota
    case transport
    case decoding
    case localNetworkDenied
    case locationUnavailable
    case unknown
}
