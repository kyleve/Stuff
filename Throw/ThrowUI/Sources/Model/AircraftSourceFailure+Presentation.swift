import ThrowCore

extension AircraftSourceFailure {
    var presentationCategory: ThrowFailureCategory {
        switch self {
            case .invalidConfiguration: .sourceNotValidated
            case .missingCredential: .missingCredential
            case .invalidCredential: .invalidCredential
            case .subscriptionRequired: .subscription
            case .entitlementRejected: .entitlement
            case .quotaReached: .quota
            case .transport(.localNetworkDenied): .localNetworkDenied
            case .provider, .transport: .transport
            case .decoding: .decoding
        }
    }
}
