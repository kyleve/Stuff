import Foundation

extension ThrowFailureCategory {
    var localizedDescription: String {
        switch self {
            case .sourceNotValidated: String(localized: .failureSourceNotValidated)
            case .missingCredential: String(localized: .failureMissingCredential)
            case .invalidCredential: String(localized: .failureInvalidCredential)
            case .subscription: String(localized: .failureSubscription)
            case .entitlement: String(localized: .failureEntitlement)
            case .quota: String(localized: .failureQuota)
            case .transport: String(localized: .failureTransport)
            case .decoding: String(localized: .failureDecoding)
            case .localNetworkDenied: String(localized: .failureLocalNetworkDenied)
            case .locationUnavailable: String(localized: .failureLocationUnavailable)
            case .unknown: String(localized: .failureUnknown)
        }
    }
}
